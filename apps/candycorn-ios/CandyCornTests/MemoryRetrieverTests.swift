import Foundation
import Testing
@testable import CandyCorn

@Suite("Vault memory retrieval")
struct MemoryRetrieverTests {
    @Test("Therapy retrieval is source-backed, filtered, ranked, and deterministic")
    func therapyRetrieval() async throws {
        let fixture = try Self.fixture()
        let store = InMemoryCareStore(snapshot: fixture.snapshot)
        let retriever = MemoryRetriever(careStore: store)

        let first = try await retriever.retrieve(fixture.request)
        let second = try await retriever.retrieve(fixture.request)

        #expect(first == second)
        #expect(first.characterCount == first.text.count)
        #expect(first.items.count <= ContextPacketLimits.appointment.maximumItems)
        #expect(first.text.count <= ContextPacketLimits.appointment.maximumCharacters)
        #expect(first.items.allSatisfy { !$0.sourceIDs.isEmpty })
        #expect(first.items.contains { $0.kind == .sessionSummary && $0.provenance == .user })
        #expect(first.items.contains { $0.id == fixture.patientSegmentID && $0.provenance == .user })
        #expect(!first.items.contains { $0.id == fixture.unknownSegmentID })
        #expect(first.omittedItemCount == 2)

        let journalItems = first.items.filter { $0.kind == .journal }
        #expect(journalItems.map(\.id) == [fixture.relevantJournalID, fixture.newerJournalID])
        #expect(journalItems.first?.text == "Cleaned sleep routine details")
        #expect(!first.items.contains { $0.id == fixture.beforeBoundaryJournalID })
        #expect(!first.items.contains { $0.id == fixture.afterWindowJournalID })

        let goals = first.items.filter { $0.kind == .homework || $0.kind == .activeGoal }
        #expect(goals.count == 2)
        #expect(first.items.contains { $0.kind == .goalProgress && $0.provenance == .candyCorn })
        let points = first.items.filter { $0.kind == .talkingPoint }
        #expect(points.map(\.title) == ["Important talking point", "Talking point"])

        let moodItems = first.items.filter { $0.kind == .moodTrend || $0.kind == .moodLog }
        #expect(moodItems.count == 2)
        #expect(moodItems.first?.text.contains("One check-in was recorded") == true)
        #expect(!first.items.contains { $0.id == fixture.beforeBoundaryMoodID })
    }

    @Test("Appointment kind isolates the last processed session")
    func appointmentKindIsolation() async throws {
        let fixture = try Self.fixture()
        let packet = try await MemoryRetriever(careStore: InMemoryCareStore(snapshot: fixture.snapshot)).retrieve(
            MemoryRetrievalRequest(appointmentKind: .tms, window: fixture.request.window, now: fixture.request.now)
        )

        #expect(!packet.items.contains { $0.kind == .sessionSummary || $0.kind == .transcriptEvidence })
        #expect(!packet.items.contains { $0.id == fixture.patientSegmentID })
    }

    @Test("Empty and unreadable-summary vaults return valid packets")
    func emptyAndUnreadableSummary() async throws {
        let request = Self.request
        let empty = try await MemoryRetriever(careStore: InMemoryCareStore(snapshot: SeededData.emptySnapshot)).retrieve(request)
        #expect(empty.items.isEmpty)
        #expect(empty.omittedItemCount == 0)
        #expect(!empty.text.isEmpty)
        #expect(empty.text.count <= ContextPacketLimits.appointment.maximumCharacters)

        var snapshot = SeededData.emptySnapshot
        let appointmentID = Self.uuid("10000000-0000-0000-0000-000000000091")
        let artifactID = Self.uuid("10000000-0000-0000-0000-000000000092")
        snapshot.appointments = [Self.appointment(id: appointmentID, summaryID: artifactID)]
        snapshot.artifacts = [AIArtifact(
            id: artifactID,
            kind: .sessionSummary,
            sourceIDs: [appointmentID],
            provider: "fixture",
            model: "fixture",
            structuredPayload: Data("not-json".utf8),
            createdAt: Self.date(110)
        )]
        let unreadable = try await MemoryRetriever(careStore: InMemoryCareStore(snapshot: snapshot)).retrieve(request)
        #expect(!unreadable.items.contains { $0.kind == .sessionSummary })
    }

    @Test("Search failure falls back to token overlap and recency")
    func searchFailureFallback() async throws {
        let fixture = try Self.fixture()
        let store = MemorySearchFailureStore(snapshot: fixture.snapshot)
        let packet = try await MemoryRetriever(careStore: store).retrieve(fixture.request)
        let journals = packet.items.filter { $0.kind == .journal }

        #expect(journals.map(\.id) == [fixture.relevantJournalID, fixture.newerJournalID])
        #expect(await store.searchCount > 0)
    }

    @Test("No open relevance items performs no search")
    func noRelevanceQueries() async throws {
        var snapshot = SeededData.emptySnapshot
        snapshot.journals = [Self.journal(
            id: Self.uuid("20000000-0000-0000-0000-000000000090"),
            at: 120,
            title: "A quiet afternoon",
            raw: "I sat outside for a while.",
            cleaned: nil
        )]
        let store = MemorySearchFailureStore(snapshot: snapshot)

        let packet = try await MemoryRetriever(careStore: store).retrieve(Self.request)

        #expect(packet.items.count == 1)
        #expect(await store.searchCount == 0)
    }

    @Test("Builder enforces category, item, character, and duplicate caps")
    func builderCaps() throws {
        let candidates = [
            Self.packetItem(id: Self.uuid("20000000-0000-0000-0000-000000000001"), text: String(repeating: "a", count: 600)),
            Self.packetItem(id: Self.uuid("20000000-0000-0000-0000-000000000002"), text: "second"),
            Self.packetItem(id: Self.uuid("20000000-0000-0000-0000-000000000003"), text: "third"),
            Self.packetItem(id: Self.uuid("20000000-0000-0000-0000-000000000003"), text: "duplicate"),
        ]
        let categoryPacket = try ContextPacketBuilder(limits: ContextPacketLimits(
            maximumItems: 2,
            maximumCharacters: 12_000,
            maximumCharactersPerItem: 5,
            maximumSearchQueries: 0,
            maximumItemsPerKind: 1
        )).build(request: Self.request, candidates: candidates)
        #expect(categoryPacket.items.count == 1)
        #expect(categoryPacket.items[0].text == "aaaaa")
        #expect(categoryPacket.omittedItemCount == 3)

        let characterPacket = try ContextPacketBuilder(limits: ContextPacketLimits(
            maximumItems: 2,
            maximumCharacters: 300,
            maximumCharactersPerItem: 1_500,
            maximumSearchQueries: 0,
            maximumItemsPerKind: 2
        )).build(request: Self.request, candidates: [candidates[0]])
        #expect(characterPacket.items.count == 1)
        #expect(characterPacket.text.count == 300)
        #expect(characterPacket.characterCount == 300)
        #expect(characterPacket.items[0].text.count < 600)
    }

    private static let request = MemoryRetrievalRequest(
        appointmentKind: .therapy,
        window: DateInterval(start: date(50), end: date(200)),
        now: date(200)
    )

    private static func fixture() throws -> MemoryFixture {
        let appointmentID = uuid("10000000-0000-0000-0000-000000000001")
        let artifactID = uuid("10000000-0000-0000-0000-000000000002")
        let patientSegmentID = uuid("10000000-0000-0000-0000-000000000003")
        let unknownSegmentID = uuid("10000000-0000-0000-0000-000000000004")
        let relevantJournalID = uuid("10000000-0000-0000-0000-000000000005")
        let newerJournalID = uuid("10000000-0000-0000-0000-000000000006")
        let beforeJournalID = uuid("10000000-0000-0000-0000-000000000007")
        let afterJournalID = uuid("10000000-0000-0000-0000-000000000008")
        let blankJournalID = uuid("10000000-0000-0000-0000-000000000009")
        let beforeMoodID = uuid("10000000-0000-0000-0000-000000000010")
        let activeGoalID = uuid("10000000-0000-0000-0000-000000000011")
        let homeworkID = uuid("10000000-0000-0000-0000-000000000012")
        let normalPointID = uuid("10000000-0000-0000-0000-000000000013")
        let importantPointID = uuid("10000000-0000-0000-0000-000000000014")
        let patientItem = StructuredSessionSummaryItem(
            id: uuid("10000000-0000-0000-0000-000000000015"),
            text: "Sleep felt steadier.",
            provenance: .patient,
            evidence: [
                EvidenceCitation(sourceID: patientSegmentID, quote: "My sleep felt steadier.", timestampMilliseconds: 1_000),
                EvidenceCitation(sourceID: patientSegmentID, quote: "My sleep felt steadier.", timestampMilliseconds: 1_000),
                EvidenceCitation(sourceID: unknownSegmentID, quote: "Unknown source words.", timestampMilliseconds: 2_000),
            ],
            relatedEntityID: nil
        )
        let providerItem = StructuredSessionSummaryItem(
            id: uuid("10000000-0000-0000-0000-000000000016"),
            text: "Keep noting the routine.",
            provenance: .provider,
            evidence: [EvidenceCitation(sourceID: patientSegmentID, quote: "My sleep felt steadier.", timestampMilliseconds: 1_000)],
            relatedEntityID: nil
        )
        let summary = StructuredSessionSummaryResult(
            template: .therapy,
            debriefTopics: [patientItem],
            sections: [StructuredSessionSummarySection(
                id: uuid("10000000-0000-0000-0000-000000000017"),
                kind: .homework,
                title: "Homework",
                items: [providerItem]
            )],
            discussedTalkingPoints: [],
            metadata: AIResultMetadata(provider: "fixture", model: "fixture", usage: AIUsage())
        )
        var snapshot = SeededData.emptySnapshot
        snapshot.appointments = [appointment(id: appointmentID, summaryID: artifactID)]
        snapshot.artifacts = [AIArtifact(
            id: artifactID,
            kind: .sessionSummary,
            sourceIDs: [appointmentID, patientSegmentID, unknownSegmentID],
            provider: "fixture",
            model: "fixture",
            structuredPayload: try PersistenceCoding.encode(summary),
            createdAt: date(110)
        )]
        snapshot.sessionProcessing = [SessionProcessingRecord(
            id: uuid("10000000-0000-0000-0000-000000000018"),
            appointmentID: appointmentID,
            stage: .ready,
            progress: 1,
            summaryConsentGranted: true,
            failure: nil,
            updatedAt: date(111)
        )]
        snapshot.transcript = [
            TranscriptSegment(id: patientSegmentID, appointmentID: appointmentID, speaker: .patient, rawSpeakerLabel: nil, startMilliseconds: 1_000, endMilliseconds: 1_500, text: "My sleep felt steadier.", confidence: 1),
            TranscriptSegment(id: unknownSegmentID, appointmentID: appointmentID, speaker: .unknown, rawSpeakerLabel: "speaker", startMilliseconds: 2_000, endMilliseconds: 2_500, text: "Unknown source words.", confidence: nil),
        ]
        snapshot.goals = [
            goal(id: activeGoalID, title: "Sleep routine", cadence: .daily, status: .active),
            goal(id: homeworkID, title: "Write the sleep log", cadence: .homework, status: .proposed),
            goal(id: uuid("10000000-0000-0000-0000-000000000019"), title: "Closed", cadence: .homework, status: .completed),
        ]
        snapshot.goalProgress = [GoalProgress(
            id: uuid("10000000-0000-0000-0000-000000000020"),
            goalID: activeGoalID,
            sourceEntryID: relevantJournalID,
            note: "Part of the routine was completed.",
            source: .aiSuggestedProgress,
            createdAt: date(160)
        )]
        snapshot.talkingPoints = [
            point(id: normalPointID, text: "Normal question", important: false),
            point(id: importantPointID, text: "Important question", important: true),
            TalkingPoint(id: uuid("10000000-0000-0000-0000-000000000021"), text: "TMS only", source: .manual, sourceID: nil, targetAppointmentKind: .tms, isImportant: true, status: .open, createdAt: date(170), provenance: provenance(.user)),
        ]
        snapshot.journals = [
            journal(id: relevantJournalID, at: 120, title: "Routine", raw: "Raw text", cleaned: "Cleaned sleep routine details"),
            journal(id: newerJournalID, at: 130, title: "Lunch", raw: "A quiet lunch outside", cleaned: nil),
            journal(id: beforeJournalID, at: 90, title: "Old", raw: "sleep routine before appointment", cleaned: nil),
            journal(id: afterJournalID, at: 220, title: "Future", raw: "sleep routine after window", cleaned: nil),
            journal(id: blankJournalID, at: 140, title: "Blank", raw: "  ", cleaned: "\n"),
        ]
        snapshot.moods = [
            MoodLog(id: beforeMoodID, createdAt: date(90), mood: 2, anxiety: nil, energy: nil, customValues: [:], note: nil),
            MoodLog(id: uuid("10000000-0000-0000-0000-000000000022"), createdAt: date(150), mood: 6, anxiety: nil, energy: nil, customValues: [:], note: nil),
        ]
        return MemoryFixture(
            snapshot: snapshot,
            request: request,
            patientSegmentID: patientSegmentID,
            unknownSegmentID: unknownSegmentID,
            relevantJournalID: relevantJournalID,
            newerJournalID: newerJournalID,
            beforeBoundaryJournalID: beforeJournalID,
            afterWindowJournalID: afterJournalID,
            beforeBoundaryMoodID: beforeMoodID
        )
    }

    private static func appointment(id: UUID, summaryID: UUID) -> Appointment {
        Appointment(
            id: id, kind: .therapy, scheduledAt: date(95), startedAt: date(95), endedAt: date(100),
            providerID: nil, providerName: "Dr. Rivera", recordingAttachmentID: nil,
            transcriptID: nil, summaryID: summaryID, status: .completed
        )
    }

    private static func goal(id: UUID, title: String, cadence: Goal.Cadence, status: Goal.Status) -> Goal {
        Goal(
            id: id, title: title, detail: nil, cadence: cadence, source: .userExplicit,
            sourceEntityID: nil, sourceTimestampMilliseconds: nil, status: status,
            createdAt: date(110), targetDate: nil, provenance: provenance(.user)
        )
    }

    private static func point(id: UUID, text: String, important: Bool) -> TalkingPoint {
        TalkingPoint(
            id: id, text: text, source: .manual, sourceID: nil, targetAppointmentKind: .therapy,
            isImportant: important, status: .open, createdAt: date(170), provenance: provenance(.user)
        )
    }

    private static func journal(id: UUID, at: TimeInterval, title: String, raw: String, cleaned: String?) -> JournalEntry {
        JournalEntry(
            id: id, createdAt: date(at), updatedAt: date(at), inputType: .text, title: title,
            rawText: raw, cleanedText: cleaned, summaryItems: [], originalAttachmentID: nil,
            audioAttachmentID: nil, moodLogID: nil, pinnedForNextAppointment: false,
            processingStatus: .processed, provenance: provenance(.user)
        )
    }

    private static func provenance(_ voice: ProvenanceVoice) -> Provenance {
        Provenance(voice: voice, label: "Fixture", detail: "Seeded fictional data", occurredAt: nil, sourceRoute: nil)
    }

    private static func packetItem(id: UUID, text: String) -> ContextPacketItem {
        ContextPacketItem(
            id: id, sourceIDs: [id], kind: .journal, title: "Journal", text: text,
            occurredAt: date(120), provenance: .user, evidence: [], relevanceRank: nil
        )
    }

    private static func uuid(_ value: String) -> UUID { UUID(uuidString: value)! }
    private static func date(_ value: TimeInterval) -> Date { Date(timeIntervalSince1970: value) }
}

private struct MemoryFixture: Sendable {
    let snapshot: CareSnapshot
    let request: MemoryRetrievalRequest
    let patientSegmentID: UUID
    let unknownSegmentID: UUID
    let relevantJournalID: UUID
    let newerJournalID: UUID
    let beforeBoundaryJournalID: UUID
    let afterWindowJournalID: UUID
    let beforeBoundaryMoodID: UUID
}

private actor MemorySearchFailureStore: CareStore {
    let value: CareSnapshot
    private(set) var searchCount = 0

    init(snapshot: CareSnapshot) { value = snapshot }

    func snapshot() -> CareSnapshot { value }
    func search(_ query: String, limit: Int) throws -> [SearchHit] {
        _ = query
        _ = limit
        searchCount += 1
        throw VaultRepositoryError.searchUnavailable
    }
    func saveJournal(_ entry: JournalEntry) { _ = entry.id }
    func deleteJournal(id: UUID) { _ = id }
    func saveMood(_ mood: MoodLog) { _ = mood.id }
    func saveAppointment(_ appointment: Appointment) { _ = appointment.id }
    func saveGoal(_ goal: Goal) { _ = goal.id }
    func addGoalProgress(_ progress: GoalProgress) { _ = progress.id }
    func saveTalkingPoint(_ point: TalkingPoint) { _ = point.id }
    func saveAttachment(_ attachment: CandyCorn.Attachment) { _ = attachment.id }
    func setSampleContentEnabled(_ enabled: Bool) { _ = enabled }
    func updateSettings(_ settings: VaultSettings) { _ = settings.useSampleContent }
}
