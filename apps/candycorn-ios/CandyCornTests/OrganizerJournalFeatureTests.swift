import Foundation
import Testing
@testable import CandyCorn

@Suite("Organizer journal features")
@MainActor
struct OrganizerJournalFeatureTests {
    @Test("Seeded artifacts decode dynamically and corrupt latest data is rejected")
    func artifactDecoding() throws {
        let journal = try #require(SeededData.journalEntries.first { $0.id == SeededData.footballJournalID })
        let decoded = try #require(JournalArtifactReader.decode(
            JournalSignalResult.self,
            kind: .journalSignals,
            journal: journal,
            artifacts: SeededData.aiArtifacts
        ))
        #expect(decoded.result.signals.talkingPointSuggestions.count == 1)
        #expect(decoded.artifact.provider == "openrouter")

        let corrupt = AIArtifact(
            id: UUID(),
            kind: .journalSignals,
            sourceIDs: [journal.id],
            provider: "fixture-router",
            model: "fixture-model",
            structuredPayload: Data([0xff, 0x00]),
            createdAt: .distantFuture
        )
        let invalid = JournalArtifactReader.decode(
            JournalSignalResult.self,
            kind: .journalSignals,
            journal: journal,
            artifacts: SeededData.aiArtifacts + [corrupt]
        )
        #expect(invalid == nil)
        #expect(journal.cleanedText != nil)
        #expect(!journal.summaryItems.isEmpty)
    }

    @Test("Candidate review removes duplicates and unsupported cadence becomes one time")
    func candidateNormalization() {
        let pointID = UUID()
        let commitmentID = UUID()
        let point = JournalSignals.TalkingPointSuggestion(
            id: pointID,
            text: "Bring up the guilt pattern",
            reason: "It was explicit.",
            evidence: "I felt guilty"
        )
        let commitment = JournalSignals.Commitment(
            id: commitmentID,
            text: "Write the next section",
            cadenceHint: "whenever the model feels like it",
            evidence: "I will write the next section"
        )
        let signals = JournalSignals(
            summary: "Summary",
            emotions: [],
            explicitCommitments: [commitment, commitment],
            talkingPointSuggestions: [point, point],
            possibleThemes: []
        )
        let review = JournalSuggestionReview(signals: signals)
        let draft = JournalCandidateDraft(candidate: commitment, journalID: UUID())

        #expect(review.talkingPoints.count == 1)
        #expect(review.commitments.count == 1)
        #expect(draft.cadence == .oneOff)
        #expect(JournalCandidateDraft.supportedCadence("every week") == .weekly)
        #expect(JournalCandidateDraft.supportedCadence("homework") == .oneOff)
    }

    @Test("Candidate Add, Edit, and Ignore remain explicit and idempotent")
    func candidateDecisions() async throws {
        let fixture = try await makeFixture()
        let journal = try #require(fixture.state.journals.first)
        let candidate = JournalSignals.Commitment(
            id: UUID(),
            text: "Write one example",
            cadenceHint: "weekly",
            evidence: "I will write one example"
        )
        var draft = JournalCandidateDraft(candidate: candidate, journalID: journal.id)
        draft.title = "Write one clear example"
        let goal = try #require(draft.makeGoal(now: fixture.now, sourceTitle: journal.title))

        #expect(await fixture.state.saveGoal(goal))
        #expect(await fixture.state.saveGoal(goal))
        #expect(fixture.state.goals.filter { $0.id == candidate.id }.count == 1)
        #expect(fixture.state.goals.first { $0.id == candidate.id }?.title == "Write one clear example")

        var decisions = JournalCandidateDecisions()
        let ignoredID = UUID()
        decisions.ignore(ignoredID)
        let ignoredCannotBegin = !decisions.begin(ignoredID)
        #expect(!decisions.isVisible(ignoredID))
        #expect(ignoredCannotBegin)
        #expect(!fixture.state.goals.contains { $0.id == ignoredID })
    }

    @Test("A talking-point suggestion creates one local item only after Add")
    func talkingPointConfirmation() async throws {
        let fixture = try await makeFixture()
        let journal = try #require(fixture.state.journals.first)
        let suggestion = JournalSignals.TalkingPointSuggestion(
            id: UUID(),
            text: "Ask why relief was followed by guilt",
            reason: "The shift appears in the journal.",
            evidence: "I felt guilty"
        )
        #expect(!fixture.state.talkingPoints.contains { $0.id == suggestion.id })
        let point = try #require(JournalSuggestionFactory.talkingPoint(
            from: suggestion,
            journalID: journal.id,
            sourceTitle: journal.title,
            target: .therapy,
            now: fixture.now
        ))

        #expect(await fixture.state.saveTalkingPoint(point))
        #expect(await fixture.state.saveTalkingPoint(point))
        #expect(fixture.state.talkingPoints.filter { $0.id == suggestion.id }.count == 1)
        #expect(fixture.state.talkingPoints.first { $0.id == suggestion.id }?.source == .aiSuggestion)
        #expect(fixture.state.talkingPoints.first { $0.id == suggestion.id }?.provenance.voice == .candyCorn)
    }

    @Test("All journal organizer sends preserve Original and require disclosure")
    func immutableOrganizerActions() async throws {
        let fixture = try await makeFixture()
        let original = try #require(fixture.state.journals.first)
        let actions: [AISendAction] = [
            .rewriteJournal(original.id),
            .summarizeJournal(original.id),
            .extractJournalSignals(original.id),
        ]
        for (index, action) in actions.enumerated() {
            let pending = try fixture.state.prepareAISend(action)
            #expect(pending.disclosure.totalCharacterCount == original.rawText.count)
            #expect(pending.disclosure.totalImageCount == 0)
            #expect(await fixture.model.callCount == index)
            #expect(await fixture.state.performAISend(pending))
        }
        let saved = try #require(fixture.state.journals.first { $0.id == original.id })
        #expect(saved.rawText == original.rawText)
        #expect(saved.originalAttachmentID == original.originalAttachmentID)
        #expect(saved.audioAttachmentID == original.audioAttachmentID)
        #expect(await fixture.model.callCount == 3)
        #expect(fixture.state.latestArtifact(kind: .journalRewrite, sourceID: original.id) != nil)
        #expect(fixture.state.latestArtifact(kind: .journalSummary, sourceID: original.id) != nil)
        #expect(fixture.state.latestArtifact(kind: .journalSignals, sourceID: original.id) != nil)
    }

    @Test("Cancel and AI Off make zero provider calls while manual capture remains usable")
    func cancelAndOffMode() async throws {
        let fixture = try await makeFixture(mode: .off, provider: .off)
        let journal = try #require(fixture.state.journals.first)
        _ = try fixture.state.prepareAISend(.rewriteJournal(journal.id))
        #expect(await fixture.model.callCount == 0)

        let pending = try fixture.state.prepareAISend(.summarizeJournal(journal.id))
        #expect(await fixture.state.performAISend(pending) == false)
        #expect(await fixture.model.callCount == 0)
        let manual = await fixture.state.createTalkingPoint(text: "Bring this up manually")
        #expect(manual != nil)
    }

    @Test("Photo extraction sends one image, persists provenance, then supplies extracted text")
    func photoOrganizerPipeline() async throws {
        let fixture = try await makeFixture(includePhoto: true)
        let photo = try #require(fixture.state.journals.first { $0.inputType == .photo })
        let attachmentID = try #require(photo.originalAttachmentID)
        let before = await fixture.store.snapshot()
        #expect(before.attachments.contains { $0.id == attachmentID })
        #expect(await fixture.vision.callCount == 0)

        let photoSend = try fixture.state.prepareAISend(.readPhoto(
            journalID: photo.id,
            attachmentID: attachmentID
        ))
        #expect(photoSend.disclosure.totalCharacterCount == 0)
        #expect(photoSend.disclosure.totalImageCount == 1)
        #expect(await fixture.vision.callCount == 0)
        #expect(await fixture.state.performAISend(photoSend))

        let photoArtifact = try #require(fixture.state.latestArtifact(kind: .photoText, sourceID: photo.id))
        #expect(photoArtifact.sourceIDs == [photo.id, attachmentID])
        #expect(photoArtifact.provider == "fixture-router")
        #expect(photoArtifact.model == "fixture-vision")
        #expect(fixture.state.journals.first { $0.id == photo.id }?.rawText == "")

        let summarySend = try fixture.state.prepareAISend(.summarizeJournal(photo.id))
        #expect(summarySend.disclosure.totalCharacterCount == JournalFeatureVisionReader.extractedText.count)
        #expect(summarySend.disclosure.totalImageCount == 0)
        #expect(await fixture.state.performAISend(summarySend))
        let source = try #require(await fixture.model.lastJournalSource)
        #expect(source.kind == .extractedPhotoText)
        #expect(source.text == JournalFeatureVisionReader.extractedText)
        let decoded = JournalArtifactReader.decode(
            JournalSummaryResult.self,
            kind: .journalSummary,
            journal: photo,
            artifacts: fixture.state.artifacts
        )
        #expect(decoded != nil)
    }

    @Test("Failed regeneration keeps prior cleaned text and a reviewed retry succeeds")
    func failureRecovery() async throws {
        let model = JournalFeatureLanguageModel(failingRewriteCount: 1)
        let fixture = try await makeFixture(model: model)
        let original = try #require(fixture.state.journals.first)
        let existingCleaned = original.cleanedText
        let failed = try fixture.state.prepareAISend(.rewriteJournal(original.id))

        #expect(await fixture.state.performAISend(failed) == false)
        #expect(fixture.state.journals.first { $0.id == original.id }?.cleanedText == existingCleaned)
        #expect(fixture.state.journals.first { $0.id == original.id }?.rawText == original.rawText)

        let retry = try fixture.state.prepareAISend(.rewriteJournal(original.id))
        #expect(await fixture.state.performAISend(retry))
        #expect(fixture.state.journals.first { $0.id == original.id }?.cleanedText == "Clearer source text.")
    }

    private func makeFixture(
        mode: AIMode = .organizer,
        provider: AIProvider = .router,
        includePhoto: Bool = false,
        model: JournalFeatureLanguageModel = JournalFeatureLanguageModel()
    ) async throws -> JournalFeatureFixture {
        var snapshot = SeededData.careSnapshot
        snapshot.artifacts = []
        snapshot.settings.aiMode = mode
        snapshot.settings.aiProvider = provider
        var imageData: [String: Data] = [:]
        if includePhoto {
            let photo = Self.photoFixture()
            snapshot.journals.insert(photo.journal, at: 0)
            snapshot.attachments.insert(photo.attachment, at: 0)
            imageData[photo.attachment.relativePath] = Data([0xff, 0xd8, 0xff, 0xd9])
        }
        let store = InMemoryCareStore(snapshot: snapshot)
        let attachments = InMemoryAttachmentStore(seedData: imageData)
        let keyStore = InMemoryOpenRouterAPIKeyStore()
        try keyStore.storeKey("fictional-test-key")
        let vision = JournalFeatureVisionReader()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
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
            visionReader: vision,
            openRouterKeyStore: keyStore,
            screenshotMode: false,
            now: { now }
        )
        let state = DemoState(dependencies: dependencies, arguments: ["CandyCorn"])
        await state.load()
        return JournalFeatureFixture(state: state, store: store, model: model, vision: vision, now: now)
    }

    private static func photoFixture() -> (journal: JournalEntry, attachment: CandyCorn.Attachment) {
        let journalID = UUID()
        let attachmentID = UUID()
        let date = Date(timeIntervalSince1970: 1_799_999_000)
        let attachment = CandyCorn.Attachment(
            id: attachmentID,
            kind: .image,
            relativePath: "images/fixture-photo.jpg",
            mediaType: "image/jpeg",
            byteCount: 4,
            durationMilliseconds: nil,
            createdAt: date,
            isSample: false
        )
        let journal = JournalEntry(
            id: journalID,
            createdAt: date,
            updatedAt: date,
            inputType: .photo,
            title: "Handwritten football notes",
            rawText: "",
            cleanedText: nil,
            summaryItems: [],
            originalAttachmentID: attachmentID,
            audioAttachmentID: nil,
            moodLogID: nil,
            pinnedForNextAppointment: false,
            processingStatus: .unprocessed,
            provenance: Provenance(
                voice: .user,
                label: "You photographed this",
                detail: "Saved on this device",
                occurredAt: date,
                sourceRoute: .journalDetail
            )
        )
        return (journal, attachment)
    }
}

@MainActor
private struct JournalFeatureFixture {
    let state: DemoState
    let store: InMemoryCareStore
    let model: JournalFeatureLanguageModel
    let vision: JournalFeatureVisionReader
    let now: Date
}

private actor JournalFeatureLanguageModel: CandyCornLanguageModel {
    nonisolated let id = "fixture-router"
    private var failingRewriteCount: Int
    private(set) var callCount = 0
    private(set) var lastJournalSource: SourceTextDocument?

    init(failingRewriteCount: Int = 0) {
        self.failingRewriteCount = failingRewriteCount
    }

    func rewriteJournal(_ input: RewriteJournalInput) throws -> RewriteJournalResult {
        callCount += 1
        lastJournalSource = input.source
        if failingRewriteCount > 0 {
            failingRewriteCount -= 1
            throw AIProviderError.serviceUnavailable
        }
        let segment = RewriteSegment(
            id: UUID(),
            text: "Clearer source text.",
            evidence: [citation(input.source)]
        )
        return RewriteJournalResult(segments: [segment], unclearAreas: [], metadata: metadata())
    }

    func summarizeJournal(_ input: JournalSummaryInput) -> JournalSummaryResult {
        callCount += 1
        lastJournalSource = input.source
        let statement = EvidenceBackedStatement(
            id: UUID(),
            text: "A short source summary.",
            evidence: [citation(input.source)]
        )
        return JournalSummaryResult(statements: [statement], metadata: metadata())
    }

    func extractJournalSignals(_ input: JournalSignalInput) -> JournalSignalResult {
        callCount += 1
        lastJournalSource = input.source
        let quote = evidence(input.source)
        let commitment = JournalSignals.Commitment(
            id: UUID(),
            text: "Write one example",
            cadenceHint: "weekly",
            evidence: quote
        )
        let point = JournalSignals.TalkingPointSuggestion(
            id: UUID(),
            text: "Bring up the pattern",
            reason: "The journal names it.",
            evidence: quote
        )
        let signals = JournalSignals(
            summary: "A source-grounded summary.",
            emotions: [],
            explicitCommitments: [commitment],
            talkingPointSuggestions: [point],
            possibleThemes: []
        )
        return JournalSignalResult(signals: signals, metadata: metadata())
    }

    func summarizeSession(_ input: SessionSummaryInput) throws -> SessionSummaryResult {
        throw AIProviderError.invalidInput
    }

    func generateAppointmentBrief(_ input: AppointmentBriefInput) throws -> AppointmentBriefResult {
        throw AIProviderError.invalidInput
    }

    private func citation(_ source: SourceTextDocument) -> EvidenceCitation {
        EvidenceCitation(sourceID: source.id, quote: evidence(source), timestampMilliseconds: nil)
    }

    private func evidence(_ source: SourceTextDocument) -> String {
        String(source.text.prefix(1_000))
    }

    private func metadata() -> AIResultMetadata {
        AIResultMetadata(
            provider: id,
            model: AIModelConfiguration.defaults.organizerModelID,
            usage: AIUsage(
                promptTokens: 20,
                completionTokens: 10,
                reasoningTokens: 5,
                totalTokens: 35,
                costCredits: 0.001
            )
        )
    }
}

private actor JournalFeatureVisionReader: CandyCornVisionReader {
    static let extractedText = "I will write one football example this week."
    nonisolated let id = "fixture-router"
    private(set) var callCount = 0

    func extractText(from input: VisionReadInput) throws -> VisionReadResult {
        callCount += 1
        guard input.mediaType == "image/jpeg", !input.imageData.isEmpty else {
            throw AIProviderError.invalidInput
        }
        return VisionReadResult(
            text: Self.extractedText,
            uncertainSpans: ["football"],
            metadata: AIResultMetadata(
                provider: id,
                model: "fixture-vision",
                usage: AIUsage(
                    promptTokens: 10,
                    completionTokens: 8,
                    reasoningTokens: 2,
                    totalTokens: 20,
                    costCredits: 0.002
                )
            )
        )
    }
}
