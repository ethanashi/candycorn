import Foundation
import GRDB
import Testing
@testable import CandyCorn

@Suite("Goal progress suggestions")
struct GoalProgressSuggesterTests {
    @Test("Journal requests prefer cleaned text and sort active goals")
    func journalRequestAssembly() async throws {
        var snapshot = Self.snapshot()
        snapshot.journals[0].cleanedText = "I completed my walk today."
        snapshot.journals[0].rawText = "Unclean version"
        snapshot.goals.append(Self.goal(id: Self.secondGoalID, title: "Call a friend"))
        snapshot.goals.append(Self.goal(id: UUID(), title: "Paused", status: .paused))
        let store = InMemoryCareStore(snapshot: snapshot)
        let suggester = GoalProgressSuggester(
            careStore: store,
            languageModel: GoalProgressLanguageModel(result: Self.validResult()),
            now: { Self.now }
        )

        let input = try await suggester.prepareInput(from: .journal(Self.journalID))

        #expect(input.sources.count == 1)
        #expect(input.sources[0].document.text == "I completed my walk today.")
        #expect(input.sources[0].startMilliseconds == nil)
        #expect(input.goals.map(\.title) == ["Call a friend", "Walk after lunch"])
        #expect(input.requestText.contains("I completed my walk today."))
        #expect(!input.requestText.contains("Unclean version"))
        #expect(!input.requestText.contains("Paused"))
    }

    @Test("Ready processed sessions send bounded transcript segments with timestamps")
    func processedSessionRequestAssembly() async throws {
        let snapshot = try Self.processedSessionSnapshot()
        let suggester = GoalProgressSuggester(
            careStore: InMemoryCareStore(snapshot: snapshot),
            languageModel: GoalProgressLanguageModel(result: Self.validResult()),
            now: { Self.now }
        )

        let input = try await suggester.prepareInput(from: .processedSession(Self.appointmentID))

        #expect(input.sources.count == 2)
        #expect(input.sources.map(\.startMilliseconds) == [100, 800])
        #expect(input.sources.map(\.endMilliseconds) == [700, 1_400])
        #expect(input.sources.map(\.document.title) == [
            "Patient transcript segment", "Provider transcript segment",
        ])
        #expect(input.requestText.contains("I completed my walk today."))
        #expect(input.requestText.contains("You said the walk was done."))
    }

    @Test("Journal, session readiness, transcript, and active-goal boundaries reject")
    func sourceBoundariesReject() async throws {
        var noGoals = Self.snapshot()
        noGoals.goals[0].status = .completed
        let missingJournal = GoalProgressSuggester(
            careStore: InMemoryCareStore(snapshot: noGoals),
            languageModel: GoalProgressLanguageModel(result: Self.validResult()),
            now: { Self.now }
        )
        await #expect(throws: AIProviderError.invalidInput) {
            _ = try await missingJournal.prepareInput(from: .journal(Self.journalID))
        }

        var blank = Self.snapshot()
        blank.journals[0].rawText = "   "
        let blankSuggester = GoalProgressSuggester(
            careStore: InMemoryCareStore(snapshot: blank),
            languageModel: GoalProgressLanguageModel(result: Self.validResult()),
            now: { Self.now }
        )
        await #expect(throws: AIProviderError.invalidInput) {
            _ = try await blankSuggester.prepareInput(from: .journal(Self.journalID))
        }

        var session = try Self.processedSessionSnapshot()
        session.sessionProcessing[0].stage = .summarizing
        let notReady = GoalProgressSuggester(
            careStore: InMemoryCareStore(snapshot: session),
            languageModel: GoalProgressLanguageModel(result: Self.validResult()),
            now: { Self.now }
        )
        await #expect(throws: AIProviderError.invalidInput) {
            _ = try await notReady.prepareInput(from: .processedSession(Self.appointmentID))
        }

        session.sessionProcessing[0].stage = .ready
        session.transcript = []
        let noTranscript = GoalProgressSuggester(
            careStore: InMemoryCareStore(snapshot: session),
            languageModel: GoalProgressLanguageModel(result: Self.validResult()),
            now: { Self.now }
        )
        await #expect(throws: AIProviderError.invalidInput) {
            _ = try await noTranscript.prepareInput(from: .processedSession(Self.appointmentID))
        }
    }

    @Test("Validator accepts all marks and forces pending resolution")
    func validMarks() throws {
        let input = try Self.validationInput()
        let suggestions = [
            Self.suggestion(id: Self.suggestionID, goalID: Self.goalID, mark: .doneToday, quote: "I completed my walk today."),
            Self.suggestion(id: UUID(), goalID: Self.secondGoalID, mark: .partial, quote: "I started the call but stopped."),
            Self.suggestion(id: UUID(), goalID: Self.thirdGoalID, mark: .blocked, quote: "The office was closed."),
        ].map {
            GoalProgressSuggestion(
                id: $0.id, goalID: $0.goalID, mark: $0.mark,
                note: $0.note, evidence: $0.evidence, resolution: .accepted
            )
        }

        let validated = try OrganizerOutputValidator().validatedGoalProgressSuggestions(suggestions, input: input)

        #expect(validated.map(\.mark) == [.partial, .blocked, .doneToday])
        #expect(validated.allSatisfy { $0.resolution == .pending })
    }

    @Test("Legacy progress records decode without a mark")
    func legacyProgressDecoding() throws {
        let legacy = GoalProgress(
            id: Self.suggestionID,
            goalID: Self.goalID,
            sourceEntryID: Self.journalID,
            note: "Legacy progress",
            source: .userConfirmed,
            createdAt: Self.now
        )
        let encoded = try JSONEncoder().encode(legacy)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["mark"] == nil)

        let decoded = try JSONDecoder().decode(GoalProgress.self, from: encoded)
        #expect(decoded == legacy)
        #expect(decoded.mark == nil)
    }

    @Test("Validator rejects invalid targets, duplicates, evidence, timestamps, and unsafe claims")
    func invalidSuggestionsReject() throws {
        let input = try Self.validationInput(sessionBounds: (100, 700))
        let base = Self.suggestion(
            id: Self.suggestionID,
            goalID: Self.goalID,
            mark: .doneToday,
            quote: "I completed my walk today.",
            timestamp: 200
        )
        let invalidBatches: [[GoalProgressSuggestion]] = [
            [Self.copy(base, goalID: UUID())],
            [base, Self.copy(base, id: UUID())],
            [Self.copy(base, quote: "fabricated")],
            [Self.copy(base, timestamp: 900)],
            [Self.copy(base, note: "You should stop taking medication.")],
            [Self.copy(base, mark: .doneToday, quote: "Maybe I will walk.")],
            [Self.copy(base, evidence: [])],
        ]
        for suggestions in invalidBatches {
            #expect(throws: AIProviderError.invalidResponse) {
                _ = try OrganizerOutputValidator().validatedGoalProgressSuggestions(suggestions, input: input)
            }
        }

        var unknownInput = input
        unknownInput = GoalProgressSuggestionInput(
            originID: unknownInput.originID,
            origin: unknownInput.origin,
            sources: [GoalProgressSourceDocument(
                document: SourceTextDocument(
                    id: Self.journalID, kind: .sessionNotes, title: "Unknown speaker transcript segment",
                    text: "I completed my walk today.", occurredAt: Self.now
                ),
                startMilliseconds: 100,
                endMilliseconds: 700
            )],
            goals: unknownInput.goals,
            requestText: unknownInput.requestText
        )
        #expect(throws: AIProviderError.invalidResponse) {
            _ = try OrganizerOutputValidator().validatedGoalProgressSuggestions([base], input: unknownInput)
        }
    }

    @Test("Consent generation persists only one pending artifact")
    @MainActor
    func generationAndAcceptance() async throws {
        let model = GoalProgressLanguageModel(result: Self.validResult())
        let fixture = try Self.stateFixture(model: model)
        await fixture.state.load()

        async let first = fixture.state.prepareGoalProgressSuggestions(from: .journal(Self.journalID))
        async let second = fixture.state.prepareGoalProgressSuggestions(from: .journal(Self.journalID))
        let pending = try await first
        let duplicate = try await second

        #expect(pending.id == duplicate.id)
        #expect(pending.disclosure.totalCharacterCount == pending.disclosure.sources[0].characterCount)
        #expect(await model.callCount == 0)
        #expect(fixture.state.pendingProgressSuggestions.isEmpty)
        #expect(await fixture.state.performAISend(pending))
        #expect(await model.callCount == 1)
        #expect(fixture.state.artifacts.filter { $0.kind == .goalProgressSuggestions }.count == 1)
        #expect(fixture.state.goalProgress.isEmpty)
        let suggestion = try #require(fixture.state.pendingProgressSuggestions.first)
        let artifact = try #require(fixture.state.artifacts.first { $0.kind == .goalProgressSuggestions })
        #expect(artifact.sourceIDs == [Self.journalID, Self.goalID])

        #expect(await fixture.state.accept(suggestionID: suggestion.id))
        #expect(fixture.state.pendingProgressSuggestions.isEmpty)
        #expect(fixture.state.goalProgress.count == 1)
        #expect(fixture.state.goalProgress[0].id == suggestion.id)
        #expect(fixture.state.goalProgress[0].mark == .doneToday)
        #expect(await fixture.state.accept(suggestionID: suggestion.id))
        #expect(fixture.state.goalProgress.count == 1)

        let retry = try await fixture.state.prepareGoalProgressSuggestions(from: .journal(Self.journalID))
        #expect(await fixture.state.performAISend(retry))
        #expect(await model.callCount == 1)
        #expect(fixture.state.artifacts.filter { $0.kind == .goalProgressSuggestions }.count == 1)

        let reloaded = DemoState(dependencies: fixture.dependencies, arguments: ["CandyCorn"])
        await reloaded.load()
        #expect(reloaded.pendingProgressSuggestions.isEmpty)
        #expect(reloaded.goalProgress.count == 1)
    }

    @Test("Dismissal persists without creating progress")
    @MainActor
    func dismissal() async throws {
        let model = GoalProgressLanguageModel(result: Self.validResult(mark: .partial))
        let fixture = try Self.stateFixture(model: model)
        await fixture.state.load()
        let pending = try await fixture.state.prepareGoalProgressSuggestions(from: .journal(Self.journalID))
        #expect(await fixture.state.performAISend(pending))
        let suggestion = try #require(fixture.state.pendingProgressSuggestions.first)

        #expect(await fixture.state.dismiss(suggestionID: suggestion.id))
        #expect(await fixture.state.dismiss(suggestionID: suggestion.id))
        #expect(fixture.state.pendingProgressSuggestions.isEmpty)
        #expect(fixture.state.goalProgress.isEmpty)
        let reloaded = DemoState(dependencies: fixture.dependencies, arguments: ["CandyCorn"])
        await reloaded.load()
        #expect(reloaded.pendingProgressSuggestions.isEmpty)
        #expect(reloaded.goalProgress.isEmpty)
    }

    @Test("AI Off and missing key make zero provider calls")
    @MainActor
    func dispatchGates() async throws {
        for gate in [DispatchGate.aiOff, .missingKey] {
            let model = GoalProgressLanguageModel(result: Self.validResult())
            let fixture = try Self.stateFixture(model: model, gate: gate)
            await fixture.state.load()
            let pending = try await fixture.state.prepareGoalProgressSuggestions(from: .journal(Self.journalID))
            #expect(!(await fixture.state.performAISend(pending)))
            #expect(await model.callCount == 0)
            #expect(fixture.state.artifacts.isEmpty)
            #expect(fixture.state.goalProgress.isEmpty)
        }
    }

    @Test("Source mutation during inference rejects the generated artifact")
    func sourceMutationRejects() async throws {
        let store = InMemoryCareStore(snapshot: Self.snapshot())
        let model = MutatingGoalProgressLanguageModel(store: store, result: Self.validResult())
        let suggester = GoalProgressSuggester(careStore: store, languageModel: model, now: { Self.now })
        let input = try await suggester.prepareInput(from: .journal(Self.journalID))

        await #expect(throws: AIProviderError.invalidInput) {
            _ = try await suggester.generate(input)
        }
        #expect(await model.callCount == 1)
        #expect(await store.snapshot().artifacts.isEmpty)
        #expect(await store.snapshot().goalProgress.isEmpty)
    }

    @Test("A paused goal makes a pending suggestion stale")
    func pausedGoalRejectsAcceptance() throws {
        var snapshot = Self.snapshot()
        snapshot.artifacts = [try Self.artifact(result: Self.validResult())]
        snapshot.goals[0].status = .paused

        #expect(throws: VaultRepositoryError.invalidInput) {
            _ = try GoalProgressResolutionPlan.make(
                snapshot: snapshot,
                suggestionID: Self.suggestionID,
                resolution: .accepted,
                now: Self.now
            )
        }
        #expect(snapshot.goalProgress.isEmpty)
    }

    @Test("Vault resolution is atomic and retry idempotent")
    func vaultResolutionTransaction() async throws {
        let (root, database, store, _, _) = try VaultTestSupport.make()
        defer { VaultTestSupport.remove(root) }
        try await store.setSampleContentEnabled(false)
        let journal = Self.snapshot().journals[0]
        let goal = Self.snapshot().goals[0]
        try await store.saveJournal(journal)
        try await store.saveGoal(goal)
        let artifact = try Self.artifact(result: Self.validResult())
        try await store.saveArtifact(artifact)

        try await store.resolveGoalProgressSuggestion(id: Self.suggestionID, as: .accepted, at: Self.now)
        try await store.resolveGoalProgressSuggestion(id: Self.suggestionID, as: .accepted, at: Self.now)
        var snapshot = try await store.snapshot()
        #expect(snapshot.goalProgress.count == 1)
        #expect(snapshot.goalProgress[0].mark == .doneToday)
        let accepted = try #require(Self.payload(in: snapshot).result.suggestions.first)
        #expect(accepted.resolution == .accepted)

        let rollbackArtifact = try Self.artifact(result: Self.validResult(id: Self.rollbackSuggestionID))
        try await store.saveArtifact(rollbackArtifact)
        try await database.write { db in
            try db.execute(sql: "CREATE TRIGGER reject_progress_resolution BEFORE UPDATE ON ai_artifacts BEGIN SELECT RAISE(ABORT, 'forced rollback'); END")
        }
        await #expect(throws: (any Error).self) {
            try await store.resolveGoalProgressSuggestion(
                id: Self.rollbackSuggestionID,
                as: .accepted,
                at: Self.now
            )
        }
        snapshot = try await store.snapshot()
        #expect(!snapshot.goalProgress.contains { $0.id == Self.rollbackSuggestionID })
        let pendingPayload = try #require(snapshot.artifacts.first { $0.id == rollbackArtifact.id })
        let decoded = try JSONDecoder().decode(
            GoalProgressSuggestionArtifactPayload.self,
            from: pendingPayload.structuredPayload
        )
        #expect(decoded.result.suggestions[0].resolution == .pending)
    }

    private enum DispatchGate { case normal, aiOff, missingKey }

    private static let now = Date(timeIntervalSince1970: 2_000)
    private static let journalID = UUID(uuidString: "a1000000-0000-0000-0000-000000000001")!
    private static let goalID = UUID(uuidString: "a1000000-0000-0000-0000-000000000002")!
    private static let secondGoalID = UUID(uuidString: "a1000000-0000-0000-0000-000000000003")!
    private static let thirdGoalID = UUID(uuidString: "a1000000-0000-0000-0000-000000000004")!
    private static let suggestionID = UUID(uuidString: "a1000000-0000-0000-0000-000000000005")!
    private static let rollbackSuggestionID = UUID(uuidString: "a1000000-0000-0000-0000-000000000006")!
    private static let appointmentID = UUID(uuidString: "a1000000-0000-0000-0000-000000000007")!

    private static func snapshot() -> CareSnapshot {
        var snapshot = SeededData.emptySnapshot
        snapshot.journals = [JournalEntry(
            id: journalID, createdAt: now, updatedAt: now, inputType: .text,
            title: "Walk journal", rawText: "I completed my walk today.", cleanedText: nil,
            summaryItems: [], originalAttachmentID: nil, audioAttachmentID: nil, moodLogID: nil,
            pinnedForNextAppointment: false, processingStatus: .processed,
            provenance: Provenance(
                voice: .user, label: "You wrote this", detail: "Fixture",
                occurredAt: now, sourceRoute: nil
            )
        )]
        snapshot.goals = [goal(id: goalID, title: "Walk after lunch")]
        return snapshot
    }

    private static func processedSessionSnapshot() throws -> CareSnapshot {
        var snapshot = Self.snapshot()
        let result = StructuredSessionSummaryResult(
            template: .therapy,
            debriefTopics: [],
            sections: [],
            discussedTalkingPoints: [],
            metadata: metadata
        )
        let data = try JSONEncoder().encode(result)
        let summaryID = UUID()
        snapshot.appointments = [Appointment(
            id: appointmentID, kind: .therapy, scheduledAt: now, startedAt: now,
            endedAt: now, providerID: nil, providerName: "Dr. Rivera",
            recordingAttachmentID: UUID(), transcriptID: UUID(), summaryID: summaryID,
            status: .completed
        )]
        snapshot.sessionProcessing = [SessionProcessingRecord(
            id: UUID(), appointmentID: appointmentID, stage: .ready, progress: 1,
            summaryConsentGranted: true, failure: nil, updatedAt: now
        )]
        snapshot.artifacts = [AIArtifact(
            id: summaryID, kind: .sessionSummary, sourceIDs: [appointmentID],
            provider: "fixture", model: "fixture/model", structuredPayload: data, createdAt: now
        )]
        snapshot.transcript = [
            TranscriptSegment(
                id: journalID, appointmentID: appointmentID, speaker: .patient,
                rawSpeakerLabel: "Speaker 1", startMilliseconds: 100, endMilliseconds: 700,
                text: "I completed my walk today.", confidence: 0.9
            ),
            TranscriptSegment(
                id: UUID(), appointmentID: appointmentID, speaker: .provider,
                rawSpeakerLabel: "Speaker 2", startMilliseconds: 800, endMilliseconds: 1_400,
                text: "You said the walk was done.", confidence: 0.9
            ),
        ]
        return snapshot
    }

    private static func goal(
        id: UUID,
        title: String,
        status: Goal.Status = .active
    ) -> Goal {
        Goal(
            id: id, title: title, detail: "Ten minutes", cadence: .daily,
            source: .userExplicit, sourceEntityID: nil, sourceTimestampMilliseconds: nil,
            status: status, createdAt: now, targetDate: nil,
            provenance: Provenance(
                voice: .user, label: "You chose this", detail: "Fixture",
                occurredAt: now, sourceRoute: nil
            )
        )
    }

    private static func validationInput(
        sessionBounds: (Int, Int)? = nil
    ) throws -> GoalProgressSuggestionInput {
        let source = GoalProgressSourceDocument(
            document: SourceTextDocument(
                id: journalID,
                kind: sessionBounds == nil ? .journal : .sessionNotes,
                title: sessionBounds == nil ? "Journal" : "Patient transcript segment",
                text: "I completed my walk today. I started the call but stopped. The office was closed. Maybe I will walk.",
                occurredAt: now
            ),
            startMilliseconds: sessionBounds?.0,
            endMilliseconds: sessionBounds?.1
        )
        let goals = [
            GoalProgressGoalContext(id: goalID, title: "Walk", detail: nil, cadence: .daily),
            GoalProgressGoalContext(id: secondGoalID, title: "Call", detail: nil, cadence: .weekly),
            GoalProgressGoalContext(id: thirdGoalID, title: "Office", detail: nil, cadence: .oneOff),
        ]
        let origin = GoalProgressSuggestionSource.journal(journalID)
        let requestText = try GoalProgressSuggester.canonicalRequestText(
            origin: origin,
            sources: [source],
            goals: goals
        )
        return GoalProgressSuggestionInput(
            originID: journalID, origin: origin, sources: [source], goals: goals, requestText: requestText
        )
    }

    private static func validResult(
        id: UUID = suggestionID,
        mark: GoalProgressMark = .doneToday
    ) -> GoalProgressSuggestionResult {
        GoalProgressSuggestionResult(
            suggestions: [suggestion(id: id, goalID: goalID, mark: mark, quote: "I completed my walk today.")],
            metadata: metadata
        )
    }

    private static var metadata: AIResultMetadata {
        AIResultMetadata(provider: "fixture", model: "fixture/model", usage: AIUsage())
    }

    private static func suggestion(
        id: UUID,
        goalID: UUID,
        mark: GoalProgressMark,
        quote: String,
        timestamp: Int? = nil
    ) -> GoalProgressSuggestion {
        GoalProgressSuggestion(
            id: id, goalID: goalID, mark: mark, note: "Evidence-backed progress",
            evidence: [EvidenceCitation(sourceID: journalID, quote: quote, timestampMilliseconds: timestamp)],
            resolution: .pending
        )
    }

    private static func copy(
        _ value: GoalProgressSuggestion,
        id: UUID? = nil,
        goalID: UUID? = nil,
        mark: GoalProgressMark? = nil,
        note: String? = nil,
        quote: String? = nil,
        timestamp: Int? = nil,
        evidence: [EvidenceCitation]? = nil
    ) -> GoalProgressSuggestion {
        let citation = value.evidence.first
        return GoalProgressSuggestion(
            id: id ?? value.id,
            goalID: goalID ?? value.goalID,
            mark: mark ?? value.mark,
            note: note ?? value.note,
            evidence: evidence ?? [EvidenceCitation(
                sourceID: citation?.sourceID ?? journalID,
                quote: quote ?? citation?.quote ?? "",
                timestampMilliseconds: timestamp ?? citation?.timestampMilliseconds
            )],
            resolution: value.resolution
        )
    }

    @MainActor
    private static func stateFixture(
        model: GoalProgressLanguageModel,
        gate: DispatchGate = .normal
    ) throws -> GoalProgressStateFixture {
        var snapshot = Self.snapshot()
        snapshot.settings.aiMode = gate == .aiOff ? .off : .organizer
        snapshot.settings.aiProvider = gate == .aiOff ? .off : .router
        let store = InMemoryCareStore(snapshot: snapshot)
        let attachments = InMemoryAttachmentStore()
        let keyStore = InMemoryOpenRouterAPIKeyStore()
        if gate != .missingKey { try keyStore.storeKey("fictional-test-key") }
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
        return GoalProgressStateFixture(
            state: DemoState(dependencies: dependencies, arguments: ["CandyCorn"]),
            dependencies: dependencies
        )
    }

    private static func artifact(result: GoalProgressSuggestionResult) throws -> AIArtifact {
        let input = try GoalProgressSuggester.makeInput(from: .journal(journalID), snapshot: snapshot())
        let payload = GoalProgressSuggestionArtifactPayload(
            origin: .journal(journalID),
            input: input,
            result: result
        )
        return AIArtifact(
            id: UUID(), kind: .goalProgressSuggestions,
            sourceIDs: [journalID] + result.suggestions.map(\.goalID),
            provider: "fixture", model: "fixture/model",
            structuredPayload: try JSONEncoder().encode(payload), createdAt: now
        )
    }

    private static func payload(in snapshot: CareSnapshot) throws -> GoalProgressSuggestionArtifactPayload {
        let artifact = try #require(snapshot.artifacts.first { artifact in
            guard artifact.kind == .goalProgressSuggestions,
                  let payload = try? JSONDecoder().decode(
                    GoalProgressSuggestionArtifactPayload.self,
                    from: artifact.structuredPayload
                  ) else { return false }
            return payload.result.suggestions.contains { $0.id == suggestionID }
        })
        return try JSONDecoder().decode(GoalProgressSuggestionArtifactPayload.self, from: artifact.structuredPayload)
    }
}

@MainActor
private struct GoalProgressStateFixture {
    let state: DemoState
    let dependencies: AppDependencies
}

private actor GoalProgressLanguageModel: CandyCornLanguageModel {
    nonisolated let id = "goal-progress-fixture"
    private let result: GoalProgressSuggestionResult
    private(set) var callCount = 0
    private(set) var input: GoalProgressSuggestionInput?

    init(result: GoalProgressSuggestionResult) { self.result = result }

    func suggestGoalProgress(_ input: GoalProgressSuggestionInput) -> GoalProgressSuggestionResult {
        callCount += 1
        self.input = input
        return result
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

    func generateAppointmentBrief(_ input: AppointmentBriefInput) throws -> AppointmentBriefResult {
        _ = input.appointmentKind
        throw AIProviderError.unavailable
    }
}

private actor MutatingGoalProgressLanguageModel: CandyCornLanguageModel {
    nonisolated let id = "mutating-goal-progress-fixture"
    private let store: InMemoryCareStore
    private let result: GoalProgressSuggestionResult
    private(set) var callCount = 0

    init(store: InMemoryCareStore, result: GoalProgressSuggestionResult) {
        self.store = store
        self.result = result
    }

    func suggestGoalProgress(_ input: GoalProgressSuggestionInput) async throws -> GoalProgressSuggestionResult {
        callCount += 1
        var snapshot = await store.snapshot()
        guard var journal = snapshot.journals.first(where: { $0.id == input.originID }) else {
            throw AIProviderError.invalidInput
        }
        journal.rawText = "The source changed during inference."
        journal.updatedAt = journal.updatedAt.addingTimeInterval(1)
        await store.saveJournal(journal)
        snapshot = await store.snapshot()
        guard snapshot.journals.contains(where: { $0 == journal }) else { throw AIProviderError.invalidInput }
        return result
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

    func generateAppointmentBrief(_ input: AppointmentBriefInput) throws -> AppointmentBriefResult {
        _ = input.appointmentKind
        throw AIProviderError.unavailable
    }
}
