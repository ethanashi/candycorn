import Foundation

actor OpenRouterVisionReader: CandyCornVisionReader {
    nonisolated let id = OpenRouterClient.providerID
    private static let maximumImageBytes = 25 * 1_024 * 1_024
    private let client: OpenRouterClient
    private let validator: OrganizerOutputValidator

    init(
        keyProvider: any OpenRouterAPIKeyProviding,
        configurationProvider: any AIConfigurationProviding,
        transport: any AIHTTPTransport,
        sleeper: any AIBackoffSleeping = TaskAIBackoffSleeper(),
        clock: any AIMonotonicClock = SystemAIMonotonicClock(),
        logger: any AIEventLogging = NoOpAIEventLogger(),
        validator: OrganizerOutputValidator = OrganizerOutputValidator()
    ) {
        self.client = OpenRouterClient(
            keyProvider: keyProvider,
            configurationProvider: configurationProvider,
            transport: transport,
            sleeper: sleeper,
            clock: clock,
            logger: logger
        )
        self.validator = validator
    }

    init(client: OpenRouterClient, validator: OrganizerOutputValidator = OrganizerOutputValidator()) {
        self.client = client
        self.validator = validator
    }

    func extractText(from input: VisionReadInput) async throws -> VisionReadResult {
        let mediaType = input.mediaType.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard mediaType.hasPrefix("image/"),
              input.imageData.count > 0,
              input.imageData.count <= Self.maximumImageBytes else {
            throw AIProviderError.invalidInput
        }
        let metadata = try sourceMetadata(input, mediaType: mediaType)
        let imageURL = "data:\(mediaType);base64,\(input.imageData.base64EncodedString())"
        let userContent: JSONValue = .array([
            .object(["type": .string("text"), "text": .string(metadata)]),
            .object([
                "type": .string("image_url"),
                "image_url": .object(["url": .string(imageURL)]),
            ]),
        ])
        let completion = try await client.complete(
            route: .vision,
            taskInstructions: "Transcribe only writing visible in this saved journal image. Preserve line order and uncertainty. Put every uncertain exact span in uncertainSpans. Do not interpret, diagnose, summarize, or add missing text.",
            userContent: userContent,
            schemaName: "photo_text",
            schema: OpenRouterSchemas.vision
        )
        let payload: VisionPayload
        do {
            payload = try JSONDecoder().decode(VisionPayload.self, from: completion.content)
        } catch {
            throw AIProviderError.invalidResponse
        }
        try validator.validateVision(text: payload.text, uncertainSpans: payload.uncertainSpans)
        return VisionReadResult(text: payload.text, uncertainSpans: payload.uncertainSpans, metadata: completion.metadata)
    }

    private func sourceMetadata(_ input: VisionReadInput, mediaType: String) throws -> String {
        let value = VisionSourceMetadata(
            journalID: input.journalID,
            attachmentID: input.attachmentID,
            mediaType: mediaType
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8), !string.isEmpty else {
            throw AIProviderError.invalidInput
        }
        return string
    }
}

private struct VisionSourceMetadata: Encodable {
    let journalID: UUID
    let attachmentID: UUID
    let mediaType: String
}

private struct VisionPayload: Decodable {
    let text: String
    let uncertainSpans: [String]
}
