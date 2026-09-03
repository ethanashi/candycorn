import Foundation
import Testing
@testable import CandyCorn

@Suite("Appointment brief vault context")
struct AppointmentBriefContextTests {
    @Test("Provider user content is the canonical packet byte for byte")
    func exactPacketPrompt() async throws {
        let packet = Self.packet()
        let transport = BriefTransport(response: Self.response(
            sourceID: Self.journalID,
            quote: "I wrote the exact journal sentence."
        ))
        let model = OpenRouterLanguageModel(
            keyProvider: BriefKeyProvider(),
            configurationProvider: BriefConfigurationProvider(),
            transport: transport
        )

        _ = try await model.generateAppointmentBrief(.init(appointmentKind: .therapy, contextPacket: packet))

        let request = try #require(await transport.requests.first)
        let bodyData = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        let messages = try #require(body["messages"] as? [[String: Any]])
        let userContent = try #require(messages.last?["content"] as? String)
        #expect(userContent == packet.text)
        #expect(!userContent.contains("appointmentKind"))
        #expect(!userContent.contains("contextPacket"))
    }

    @Test("Unknown, empty, and fabricated citations reject the whole brief")
    func invalidCitationsReject() async {
        let packet = Self.packet()
        let invalidResponses = [
            Self.response(sourceID: UUID(), quote: "I wrote the exact journal sentence."),
            Self.response(sourceID: Self.journalID, quote: ""),
            Self.response(sourceID: Self.journalID, quote: "This quote was fabricated."),
        ]
        for response in invalidResponses {
            let model = OpenRouterLanguageModel(
                keyProvider: BriefKeyProvider(),
                configurationProvider: BriefConfigurationProvider(),
                transport: BriefTransport(response: response)
            )
            await #expect(throws: AIProviderError.invalidResponse) {
                _ = try await model.generateAppointmentBrief(.init(
                    appointmentKind: .therapy,
                    contextPacket: packet
                ))
            }
        }
    }

    @Test("Consent preparation, artifact citations, editing, and reload preserve sources")
    @MainActor
    func consentPersistenceRoundTrip() async throws {
        let model = BriefLanguageModel()
        let fixture = try Self.stateFixture(model: model)
        await fixture.state.load()

        async let first = fixture.state.prepareAppointmentBriefSend(kind: .therapy)
        async let second = fixture.state.prepareAppointmentBriefSend(kind: .therapy)
        let pending = try await first
        let duplicate = try await second

        #expect(pending.id == duplicate.id)
        #expect(pending.disclosure.sources.count == 1)
        #expect(pending.disclosure.totalCharacterCount == pending.disclosure.sources[0].characterCount)
        #expect(await model.callCount == 0)
        #expect(await fixture.state.performAISend(pending))

        let input = try #require(await model.input)
        #expect(pending.disclosure.totalCharacterCount == input.contextPacket.text.count)
        #expect(pending.disclosure.omittedSourceCount == input.contextPacket.omittedItemCount)
        let artifact = try #require(fixture.state.artifacts.first { $0.kind == .appointmentBrief })
        #expect(artifact.sourceIDs == input.contextPacket.items.map(\.id))
        let selected = AppointmentBriefArtifactReader.latest(
            kind: .therapy,
            preferredID: artifact.id,
            artifacts: fixture.state.artifacts,
            appointments: fixture.state.appointments,
            goals: fixture.state.goals,
            talkingPoints: fixture.state.talkingPoints
        )
        let selectedArtifact = try #require(selected)
        var editor = try #require(AppointmentBriefEditor(artifact: selectedArtifact))
        let statement = try #require(editor.saved.sections.first?.statements.first)
        let citations = statement.evidence
        editor.begin()
        editor.update(sectionID: editor.saved.sections[0].id, statementID: statement.id, text: "Edited locally.")
        let preparedEdit = editor.preparedSave(at: Self.now)
        let edited = try #require(preparedEdit)
        #expect(edited.sections[0].statements[0].evidence == citations)
        #expect(await fixture.state.saveEditedAppointmentBrief(artifact.id, result: edited))

        let reloaded = DemoState(dependencies: fixture.dependencies, arguments: ["CandyCorn"])
        await reloaded.load()
        let savedArtifact = try #require(reloaded.artifacts.first { $0.id == artifact.id })
        let savedEditor = try #require(AppointmentBriefEditor(artifact: savedArtifact))
        #expect(savedEditor.saved.sections[0].statements[0].text == "Edited locally.")
        #expect(savedEditor.saved.sections[0].statements[0].evidence == citations)
        #expect(savedArtifact.sourceIDs == artifact.sourceIDs)
    }

    @Test("Empty vault cannot prepare a consent send")
    @MainActor
    func emptyVaultRejectsPreparation() async throws {
        let model = BriefLanguageModel()
        let fixture = try Self.stateFixture(model: model, includeSources: false)
        await fixture.state.load()

        await #expect(throws: UserFacingError.aiSource) {
            _ = try await fixture.state.prepareAppointmentBriefSend(kind: .therapy)
        }
        #expect(await model.callCount == 0)
        #expect(fixture.state.artifacts.isEmpty)
    }

    @Test("Manual therapy and TMS briefs project exact packet text without seeded fallback")
    func manualPacketProjection() {
        let packet = Self.projectionPacket()
        let therapy = TherapyBrief(packet: packet)
        let tms = TMSBrief(packet: packet)

        #expect(therapy.whereLeftOff == "Last session exact.\n\nTranscript exact.")
        #expect(therapy.whatChanged == "Journal exact.\n\nMood trend exact.\n\nMood log exact.")
        #expect(therapy.pinnedQuestion == "Question exact.")
        #expect(therapy.carryingForward == "Homework exact.\n\nGoal exact.\n\nProgress exact.")
        #expect(therapy.possibleOpening == "Last session exact.")
        #expect(tms.observations == "Journal exact.\n\nMood trend exact.\n\nMood log exact.")
        #expect(tms.question == "Question exact.")
        #expect(tms.providerFocus == "Homework exact.\n\nGoal exact.\n\nProgress exact.")
        #expect(![therapy.whereLeftOff, therapy.whatChanged, tms.observations].joined().contains("Jamie Rivera"))
    }

    private static let now = Date(timeIntervalSince1970: 2_000)
    private static let journalID = UUID(uuidString: "91000000-0000-0000-0000-000000000001")!
    private static let pointID = UUID(uuidString: "91000000-0000-0000-0000-000000000002")!

    private static func packet() -> ContextPacket {
        let request = MemoryRetrievalRequest(
            appointmentKind: .therapy,
            window: DateInterval(start: Date(timeIntervalSince1970: 1_000), end: now),
            now: now
        )
        let item = ContextPacketItem(
            id: journalID,
            sourceIDs: [journalID],
            kind: .journal,
            title: "Exact journal",
            text: "I wrote the exact journal sentence.",
            occurredAt: Date(timeIntervalSince1970: 1_500),
            provenance: .user,
            evidence: [],
            relevanceRank: 1
        )
        return ContextPacket(
            request: request,
            items: [item],
            text: "Canonical packet\nwith punctuation: {not a wrapper}.\nI wrote the exact journal sentence.",
            omittedItemCount: 4
        )
    }

    private static func projectionPacket() -> ContextPacket {
        let values: [(ContextPacketItem.Kind, String, ProvenanceVoice)] = [
            (.sessionSummary, "Last session exact.", .user),
            (.transcriptEvidence, "Transcript exact.", .provider),
            (.homework, "Homework exact.", .provider),
            (.activeGoal, "Goal exact.", .user),
            (.goalProgress, "Progress exact.", .user),
            (.talkingPoint, "Question exact.", .user),
            (.journal, "Journal exact.", .user),
            (.moodTrend, "Mood trend exact.", .candyCorn),
            (.moodLog, "Mood log exact.", .user),
        ]
        let items = values.enumerated().map { index, value in
            let id = UUID(uuidString: String(format: "92000000-0000-0000-0000-%012d", index + 1))!
            return ContextPacketItem(
                id: id,
                sourceIDs: [id],
                kind: value.0,
                title: value.0.rawValue,
                text: value.1,
                occurredAt: now,
                provenance: value.2,
                evidence: [],
                relevanceRank: nil
            )
        }
        return ContextPacket(
            request: MemoryRetrievalRequest(
                appointmentKind: .therapy,
                window: DateInterval(start: now, end: now),
                now: now
            ),
            items: items,
            text: items.map(\.text).joined(separator: "\n"),
            omittedItemCount: 0
        )
    }

    @MainActor
    private static func stateFixture(
        model: BriefLanguageModel,
        includeSources: Bool = true
    ) throws -> BriefStateFixture {
        var snapshot = SeededData.emptySnapshot
        snapshot.settings.aiMode = .organizer
        snapshot.settings.aiProvider = .router
        if includeSources {
            snapshot.journals = [JournalEntry(
                id: journalID,
                createdAt: Date(timeIntervalSince1970: 1_500),
                updatedAt: Date(timeIntervalSince1970: 1_500),
                inputType: .text,
                title: "Exact journal",
                rawText: "I wrote the exact journal sentence.",
                cleanedText: nil,
                summaryItems: [],
                originalAttachmentID: nil,
                audioAttachmentID: nil,
                moodLogID: nil,
                pinnedForNextAppointment: false,
                processingStatus: .processed,
                provenance: Provenance(
                    voice: .user,
                    label: "You wrote this",
                    detail: "Fixture",
                    occurredAt: nil,
                    sourceRoute: nil
                )
            )]
            snapshot.talkingPoints = [TalkingPoint(
                id: pointID,
                text: "Question exact.",
                source: .manual,
                sourceID: nil,
                targetAppointmentKind: .therapy,
                isImportant: true,
                status: .open,
                createdAt: Date(timeIntervalSince1970: 1_600),
                provenance: Provenance(
                    voice: .user,
                    label: "You pinned this",
                    detail: "Fixture",
                    occurredAt: nil,
                    sourceRoute: nil
                )
            )]
        }
        let store = InMemoryCareStore(snapshot: snapshot)
        let attachments = InMemoryAttachmentStore()
        let keyStore = InMemoryOpenRouterAPIKeyStore()
        try keyStore.storeKey("fictional-test-key")
        let dependencies = AppDependencies(
            careStore: store,
            maintenance: store,
            attachments: attachments,
            recording: FakeRecordingService(attachments: attachments),
            playback: FakeAudioPlaybackService(),
            photos: FakePhotoAttachmentService(),
            exporter: FakeVaultExporter(store: store, attachments: attachments),
            logger: NoOpEventLogger(),
            languageModel: model,
            openRouterKeyStore: keyStore,
            screenshotMode: false,
            now: { now }
        )
        return BriefStateFixture(
            state: DemoState(dependencies: dependencies, arguments: ["CandyCorn"]),
            dependencies: dependencies
        )
    }

    private static func response(sourceID: UUID, quote: String) -> Data {
        let payload: [String: Any] = [
            "sections": [[
                "id": "93000000-0000-0000-0000-000000000001",
                "title": "Prepare",
                "statements": [[
                    "id": "93000000-0000-0000-0000-000000000002",
                    "text": "I wrote the exact journal sentence.",
                    "evidence": [[
                        "sourceID": sourceID.uuidString.lowercased(),
                        "quote": quote,
                        "timestampMilliseconds": NSNull(),
                    ]],
                ]],
            ]],
        ]
        let content = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data()
        let contentString = String(data: content, encoding: .utf8) ?? ""
        let envelope: [String: Any] = [
            "model": "fixture/model",
            "choices": [["message": ["content": contentString], "finish_reason": "stop"]],
        ]
        return (try? JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])) ?? Data()
    }
}

@MainActor
private struct BriefStateFixture {
    let state: DemoState
    let dependencies: AppDependencies
}

private actor BriefLanguageModel: CandyCornLanguageModel {
    nonisolated let id = "brief-fixture"
    private(set) var callCount = 0
    private(set) var input: AppointmentBriefInput?

    func generateAppointmentBrief(_ input: AppointmentBriefInput) throws -> AppointmentBriefResult {
        callCount += 1
        self.input = input
        guard let source = input.sources.first else { throw AIProviderError.invalidInput }
        return AppointmentBriefResult(
            sections: [AppointmentBriefSection(
                id: UUID(),
                title: "Prepare",
                statements: [EvidenceBackedStatement(
                    id: UUID(),
                    text: source.text,
                    evidence: [EvidenceCitation(sourceID: source.id, quote: source.text, timestampMilliseconds: nil)]
                )]
            )],
            userEditedAt: nil,
            metadata: AIResultMetadata(provider: id, model: "fixture/model", usage: AIUsage())
        )
    }

    func rewriteJournal(_ input: RewriteJournalInput) throws -> RewriteJournalResult {
        _ = input.source.id
        throw AIProviderError.unavailable
    }

    func summarizeJournal(_ input: JournalSummaryInput) throws -> JournalSummaryResult {
        _ = input.source.id
        throw AIProviderError.unavailable
    }

    func extractJournalSignals(_ input: JournalSignalInput) throws -> JournalSignalResult {
        _ = input.source.id
        throw AIProviderError.unavailable
    }

    func summarizeSession(_ input: SessionSummaryInput) throws -> SessionSummaryResult {
        _ = input.appointmentID
        throw AIProviderError.unavailable
    }
}

private actor BriefTransport: AIHTTPTransport {
    private let response: Data
    private(set) var requests: [URLRequest] = []

    init(response: Data) { self.response = response }

    func send(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard let url = request.url, let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        ) else { throw URLError(.badServerResponse) }
        return (self.response, response)
    }
}

private struct BriefKeyProvider: OpenRouterAPIKeyProviding {
    func readKey() throws -> String? { "fictional-test-key" }
    func storeKey(_ value: String) throws { _ = value }
    func removeKey() throws {}
    func hasKey() throws -> Bool { true }
}

private struct BriefConfigurationProvider: AIConfigurationProviding {
    func load() -> AIModelConfiguration { .defaults }
    func save(_ configuration: AIModelConfiguration) throws { _ = configuration }
    func reset() throws {}
}
