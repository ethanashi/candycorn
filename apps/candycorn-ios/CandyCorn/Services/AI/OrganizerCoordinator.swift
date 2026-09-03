import Foundation

enum OrganizerJournalMutation: Equatable, Sendable {
    case cleanedText(String)
    case summaryItems([String])
}

struct OrganizerWorkProduct: Equatable, Sendable {
    let artifact: AIArtifact
    let journalMutation: OrganizerJournalMutation?
}

actor OrganizerCoordinator {
    private static let maximumImageBytes = 25 * 1_024 * 1_024
    private let careStore: any CareStore
    private let attachments: any AttachmentStore
    private let languageModel: any CandyCornLanguageModel
    private let visionReader: any CandyCornVisionReader
    private let now: @Sendable () -> Date

    init(
        careStore: any CareStore,
        attachments: any AttachmentStore,
        languageModel: any CandyCornLanguageModel,
        visionReader: any CandyCornVisionReader,
        now: @escaping @Sendable () -> Date
    ) {
        self.careStore = careStore
        self.attachments = attachments
        self.languageModel = languageModel
        self.visionReader = visionReader
        self.now = now
    }

    func rewriteJournal(_ source: SourceTextDocument) async throws -> OrganizerWorkProduct {
        try Self.validate(source)
        let result = try await languageModel.rewriteJournal(.init(source: source, preserveExplicitLanguage: true))
        let cleaned = result.segments.map(\.text).joined(separator: "\n\n")
        guard !cleaned.isEmpty else { throw AIProviderError.invalidResponse }
        let artifact = try makeArtifact(.journalRewrite, sourceIDs: [source.id], payload: result, metadata: result.metadata)
        return OrganizerWorkProduct(artifact: artifact, journalMutation: .cleanedText(cleaned))
    }

    func summarizeJournal(_ source: SourceTextDocument) async throws -> OrganizerWorkProduct {
        try Self.validate(source)
        let result = try await languageModel.summarizeJournal(.init(source: source))
        let items = result.statements.map(\.text)
        guard !items.isEmpty else { throw AIProviderError.invalidResponse }
        let artifact = try makeArtifact(.journalSummary, sourceIDs: [source.id], payload: result, metadata: result.metadata)
        return OrganizerWorkProduct(artifact: artifact, journalMutation: .summaryItems(items))
    }

    func extractJournalSignals(_ source: SourceTextDocument) async throws -> OrganizerWorkProduct {
        try Self.validate(source)
        let result = try await languageModel.extractJournalSignals(.init(source: source))
        let artifact = try makeArtifact(.journalSignals, sourceIDs: [source.id], payload: result, metadata: result.metadata)
        return OrganizerWorkProduct(artifact: artifact, journalMutation: nil)
    }

    func readPhoto(journalID: UUID, attachment: Attachment) async throws -> OrganizerWorkProduct {
        guard attachment.kind == .image, attachment.byteCount > 0 else { throw AIProviderError.invalidInput }
        let url = try await attachments.url(for: attachment)
        guard url.isFileURL else { throw AIProviderError.invalidInput }
        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw AIProviderError.invalidInput
        }
        guard !data.isEmpty, data.count <= Self.maximumImageBytes else { throw AIProviderError.invalidInput }
        let result = try await visionReader.extractText(from: VisionReadInput(
            journalID: journalID,
            attachmentID: attachment.id,
            mediaType: attachment.mediaType,
            imageData: data
        ))
        let artifact = try makeArtifact(
            .photoText,
            sourceIDs: [journalID, attachment.id],
            payload: result,
            metadata: result.metadata
        )
        return OrganizerWorkProduct(artifact: artifact, journalMutation: nil)
    }

    func summarizeSession(_ input: SessionSummaryInput) async throws -> OrganizerWorkProduct {
        try Self.validate(input.manualNotes)
        let result = try await languageModel.summarizeSession(input)
        let artifact = try makeArtifact(
            .sessionSummary,
            sourceIDs: [input.appointmentID],
            payload: result,
            metadata: result.metadata
        )
        return OrganizerWorkProduct(artifact: artifact, journalMutation: nil)
    }

    func generateAppointmentBrief(_ input: AppointmentBriefInput) async throws -> OrganizerWorkProduct {
        guard !input.sources.isEmpty else { throw AIProviderError.invalidInput }
        for source in input.sources.prefix(100_000) { try Self.validate(source) }
        guard input.sources.count <= 100_000 else { throw AIProviderError.invalidInput }
        let result = try await languageModel.generateAppointmentBrief(input)
        let artifact = try makeArtifact(
            .appointmentBrief,
            sourceIDs: input.sources.map(\.id),
            payload: result,
            metadata: result.metadata
        )
        return OrganizerWorkProduct(artifact: artifact, journalMutation: nil)
    }

    func persist(_ product: OrganizerWorkProduct) async throws {
        guard !product.artifact.structuredPayload.isEmpty else { throw AIProviderError.invalidResponse }
        try await careStore.saveArtifact(product.artifact)
    }

    func replaceArtifact(_ artifact: AIArtifact) async throws {
        guard !artifact.structuredPayload.isEmpty, !artifact.sourceIDs.isEmpty else {
            throw AIProviderError.invalidInput
        }
        try await careStore.saveArtifact(artifact)
    }

    func deleteArtifact(id: UUID) async throws {
        try await careStore.deleteArtifact(id: id)
    }

    private func makeArtifact<Payload: Encodable>(
        _ kind: AIArtifact.Kind,
        sourceIDs: [UUID],
        payload: Payload,
        metadata: AIResultMetadata
    ) throws -> AIArtifact {
        let provider = metadata.provider.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = metadata.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceIDs.isEmpty, !provider.isEmpty, !model.isEmpty else { throw AIProviderError.invalidResponse }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(payload)
        guard !data.isEmpty else { throw AIProviderError.invalidResponse }
        return AIArtifact(
            id: UUID(), kind: kind, sourceIDs: sourceIDs, provider: provider,
            model: model, structuredPayload: data, createdAt: now()
        )
    }

    private static func validate(_ source: SourceTextDocument) throws {
        let title = source.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = source.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !text.isEmpty, text.count <= 50_000 else { throw AIProviderError.invalidInput }
    }
}

struct UnavailableVisionReader: CandyCornVisionReader {
    let id = "unavailable-vision-reader"

    func extractText(from input: VisionReadInput) async throws -> VisionReadResult {
        guard input.imageData.count > 0, input.mediaType.hasPrefix("image/") else {
            throw AIProviderError.invalidInput
        }
        throw AIProviderError.unavailable
    }
}
