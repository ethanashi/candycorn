import Foundation
import Testing
@testable import CandyCorn

@Suite("Organizer workflows")
@MainActor
struct OrganizerWorkflowTests {
    @Test("Disclosure is exact and cancel has no side effect")
    func exactJournalDisclosure() async throws {
        let fixture = try await makeFixture()
        let journal = try #require(fixture.state.journals.first)
        let before = await fixture.store.snapshot()

        let pending = try fixture.state.prepareAISend(.rewriteJournal(journal.id))

        #expect(pending.disclosure.purpose == "Rewrite this journal")
        #expect(pending.disclosure.destination == "OpenRouter")
        #expect(pending.disclosure.sources.map(\.title) == [journal.title])
        #expect(pending.disclosure.totalCharacterCount == journal.rawText.count)
        #expect(pending.disclosure.totalImageCount == 0)
        #expect(pending.disclosure.omittedSourceCount == 0)
        #expect(await fixture.store.snapshot() == before)
        #expect(await fixture.model.callCount == 0)
    }

    @Test("Rewrite saves provenance before derived text and preserves the source")
    func rewritePersistence() async throws {
        let fixture = try await makeFixture()
        let original = try #require(fixture.state.journals.first)
        let pending = try fixture.state.prepareAISend(.rewriteJournal(original.id))

        #expect(await fixture.state.performAISend(pending))

        let stored = await fixture.store.snapshot()
        let journal = try #require(stored.journals.first { $0.id == original.id })
        let artifact = try #require(stored.artifacts.first { $0.kind == .journalRewrite })
        #expect(journal.rawText == original.rawText)
        #expect(journal.originalAttachmentID == original.originalAttachmentID)
        #expect(journal.audioAttachmentID == original.audioAttachmentID)
        #expect(journal.cleanedText == "Organized without changing the source.")
        #expect(artifact.provider == "fixture-router")
        #expect(artifact.model == AIModelConfiguration.defaults.organizerModelID)
        #expect(artifact.sourceIDs == [original.id])
        #expect(fixture.state.aiProcessingState(for: pending.action) == .succeeded)
    }

    @Test("AI Off and a missing key fail before provider dispatch")
    func localDispatchGates() async throws {
        let off = try await makeFixture(mode: .off, provider: .off)
        let offJournal = try #require(off.state.journals.first)
        let offPending = try off.state.prepareAISend(.summarizeJournal(offJournal.id))
        #expect(await off.state.performAISend(offPending) == false)
        #expect(await off.model.callCount == 0)

        let missing = try await makeFixture(key: nil)
        let missingJournal = try #require(missing.state.journals.first)
        let missingPending = try missing.state.prepareAISend(.summarizeJournal(missingJournal.id))
        #expect(await missing.state.performAISend(missingPending) == false)
        #expect(await missing.model.callCount == 0)
    }

    @Test("Duplicate sends make one call and an edited source rejects the result")
    func duplicateAndStaleSend() async throws {
        let model = OrganizerFixtureLanguageModel(paused: true)
        let fixture = try await makeFixture(model: model)
        let journal = try #require(fixture.state.journals.first)
        let first = try fixture.state.prepareAISend(.rewriteJournal(journal.id))
        let duplicate = try fixture.state.prepareAISend(.rewriteJournal(journal.id))

        let firstTask = Task { await fixture.state.performAISend(first) }
        await waitForCall(model)
        #expect(await fixture.state.performAISend(duplicate) == false)
        #expect(await fixture.state.editJournal(id: journal.id, rawText: journal.rawText + " Edited locally."))
        await model.release()

        #expect(await firstTask.value == false)
        #expect(await model.callCount == 1)
        let stored = await fixture.store.snapshot()
        #expect(stored.artifacts.isEmpty)
        #expect(stored.journals.first { $0.id == journal.id }?.rawText.hasSuffix("Edited locally.") == true)
    }

    @Test("Session summary sends manual notes only")
    func manualSessionNotesOnly() async throws {
        let fixture = try await makeFixture()
        let session = try #require(fixture.state.appointments.first { !$0.manualNotes.isEmpty })
        let pending = try fixture.state.prepareAISend(.summarizeSession(session.id))

        #expect(await fixture.state.performAISend(pending))

        let input = try #require(await fixture.model.sessionInput)
        #expect(input.manualNotes.text == session.manualNotes)
        #expect(input.manualNotes.text.contains("Speaker 1") == false)
        #expect(pending.disclosure.totalCharacterCount == session.manualNotes.count)
        let artifact = try #require(fixture.state.latestArtifact(kind: .sessionSummary, sourceID: session.id))
        #expect(artifact.sourceIDs == [session.id])
    }

    @Test("Appointment brief keeps required context and uses its appointment boundary")
    func appointmentBriefSelection() async throws {
        let fixture = try await makeFixture()
        let pending = try fixture.state.prepareAISend(.generateAppointmentBrief(.therapy))

        #expect(await fixture.state.performAISend(pending))

        let input = try #require(await fixture.model.briefInput)
        let kinds = input.sources.map(\.kind)
        #expect(input.appointmentKind == .therapy)
        #expect(kinds.contains(.sessionNotes))
        #expect(kinds.contains(.homework))
        #expect(kinds.contains(.goal))
        #expect(kinds.contains(.talkingPoint))
        #expect(kinds.contains(.moodTrend))
        #expect(kinds.filter { $0 == .journal }.count == 2)
        #expect(input.sources.contains { $0.text.contains("Riverbend TMS") } == false)
        #expect(pending.disclosure.totalCharacterCount == input.sources.reduce(0) { $0 + $1.text.count })
    }

    @Test("Photo disclosure sends one image and extraction preserves it")
    func photoExtraction() async throws {
        let dependencies = PreviewDependencies.make(screenshotMode: true, scenario: .photoSend)
        let state = DemoState(dependencies: dependencies, arguments: ["CandyCorn", "-screen", "/journal/entry/football-and-guilt", "-sheet", "photo-send"])
        await state.load()
        state.setAIMode(.organizer)
        state.setAIProvider(.router)
        let action = AISendAction.readPhoto(
            journalID: ScreenshotScenario.photoJournalID,
            attachmentID: ScreenshotScenario.photoAttachmentID
        )
        let pending = try state.prepareAISend(action)
        let original = try #require(state.journals.first { $0.id == ScreenshotScenario.photoJournalID })

        #expect(pending.disclosure.totalCharacterCount == 0)
        #expect(pending.disclosure.totalImageCount == 1)
        #expect(await state.performAISend(pending))

        let stored = try await dependencies.careStore.snapshot()
        let artifact = try #require(stored.artifacts.first { $0.kind == .photoText })
        #expect(artifact.sourceIDs == [ScreenshotScenario.photoJournalID, ScreenshotScenario.photoAttachmentID])
        #expect(stored.journals.first { $0.id == original.id }?.rawText == original.rawText)
        #expect(stored.attachments.first { $0.id == ScreenshotScenario.photoAttachmentID } != nil)
    }

    @Test("Delete everything clears secure AI configuration")
    func deleteEverythingClearsAI() async throws {
        let configuration = InMemoryAIConfigurationStore(value: AIModelConfiguration(
            organizerModelID: "fixture/custom-organizer",
            visionModelID: "fixture/custom-vision"
        ))
        let fixture = try await makeFixture(configuration: configuration)

        #expect(await fixture.state.deleteEverything(typedText: "DELETE"))
        #expect(try fixture.keyStore.hasKey() == false)
        #expect(configuration.load() == .defaults)
        #expect(fixture.state.hasOpenRouterKey == false)
        #expect(fixture.state.aiConfiguration == .defaults)
    }

    private func makeFixture(
        mode: AIMode = .organizer,
        provider: AIProvider = .router,
        key: String? = "fictional-test-key",
        model: OrganizerFixtureLanguageModel = OrganizerFixtureLanguageModel(),
        configuration: InMemoryAIConfigurationStore = InMemoryAIConfigurationStore()
    ) async throws -> OrganizerFixture {
        var snapshot = SeededData.careSnapshot
        snapshot.artifacts = []
        snapshot.settings.aiMode = mode
        snapshot.settings.aiProvider = provider
        let store = InMemoryCareStore(snapshot: snapshot)
        let attachments = InMemoryAttachmentStore()
        let keyStore = InMemoryOpenRouterAPIKeyStore()
        if let key { try keyStore.storeKey(key) }
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
            aiConfigurationStore: configuration,
            screenshotMode: false,
            now: { Date(timeIntervalSince1970: 1_788_654_600) }
        )
        let state = DemoState(dependencies: dependencies, arguments: ["CandyCorn"])
        await state.load()
        return OrganizerFixture(state: state, store: store, model: model, keyStore: keyStore)
    }

    private func waitForCall(_ model: OrganizerFixtureLanguageModel) async {
        for _ in 0..<1_000 {
            if await model.callCount > 0 { return }
            await Task.yield()
        }
        Issue.record("Provider call did not start")
    }
}

@MainActor
private struct OrganizerFixture {
    let state: DemoState
    let store: InMemoryCareStore
    let model: OrganizerFixtureLanguageModel
    let keyStore: InMemoryOpenRouterAPIKeyStore
}

private actor OrganizerFixtureLanguageModel: CandyCornLanguageModel {
    nonisolated let id = "fixture-router"
    private let paused: Bool
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var callCount = 0
    private(set) var sessionInput: SessionSummaryInput?
    private(set) var briefInput: AppointmentBriefInput?

    init(paused: Bool = false) {
        self.paused = paused
    }

    func rewriteJournal(_ input: RewriteJournalInput) async throws -> RewriteJournalResult {
        callCount += 1
        if paused { await withCheckedContinuation { continuation = $0 } }
        let segment = RewriteSegment(id: UUID(), text: "Organized without changing the source.", evidence: [citation(input.source)])
        return RewriteJournalResult(segments: [segment], unclearAreas: [], metadata: metadata())
    }

    func summarizeJournal(_ input: JournalSummaryInput) throws -> JournalSummaryResult {
        callCount += 1
        return JournalSummaryResult(statements: [statement(input.source)], metadata: metadata())
    }

    func extractJournalSignals(_ input: JournalSignalInput) throws -> JournalSignalResult {
        callCount += 1
        let quote = evidence(input.source)
        let signals = JournalSignals(
            summary: "A grounded summary.",
            emotions: [.init(label: "Feeling", evidence: quote)],
            explicitCommitments: [],
            talkingPointSuggestions: [],
            possibleThemes: []
        )
        return JournalSignalResult(signals: signals, metadata: metadata())
    }

    func summarizeSession(_ input: SessionSummaryInput) throws -> SessionSummaryResult {
        callCount += 1
        sessionInput = input
        let section = SessionSummarySection(id: UUID(), title: "Session", statements: [statement(input.manualNotes)])
        return SessionSummaryResult(sections: [section], metadata: metadata())
    }

    func generateAppointmentBrief(_ input: AppointmentBriefInput) throws -> AppointmentBriefResult {
        callCount += 1
        briefInput = input
        guard let source = input.sources.first else { throw AIProviderError.invalidInput }
        let section = AppointmentBriefSection(id: UUID(), title: "Prepare", statements: [statement(source)])
        return AppointmentBriefResult(sections: [section], userEditedAt: nil, metadata: metadata())
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }

    private func metadata() -> AIResultMetadata {
        AIResultMetadata(
            provider: id,
            model: AIModelConfiguration.defaults.organizerModelID,
            usage: AIUsage(promptTokens: 10, completionTokens: 5, reasoningTokens: 2, totalTokens: 17, costCredits: 0.001)
        )
    }

    private func statement(_ source: SourceTextDocument) -> EvidenceBackedStatement {
        EvidenceBackedStatement(id: UUID(), text: "Organized from the supplied source.", evidence: [citation(source)])
    }

    private func citation(_ source: SourceTextDocument) -> EvidenceCitation {
        EvidenceCitation(sourceID: source.id, quote: evidence(source), timestampMilliseconds: nil)
    }

    private func evidence(_ source: SourceTextDocument) -> String {
        String(source.text.prefix(1_000))
    }
}
