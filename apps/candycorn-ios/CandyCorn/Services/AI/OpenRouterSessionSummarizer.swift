import Foundation

actor OpenRouterSessionSummarizer: CandyCornSessionSummarizer {
    nonisolated let id = "openrouter-session-organizer"

    private static let maximumRequestBytes = 262_144
    private let client: OpenRouterClient
    private let validator: StructuredSessionSummaryValidator

    init(
        keyProvider: any OpenRouterAPIKeyProviding,
        configurationProvider: any AIConfigurationProviding,
        transport: any AIHTTPTransport,
        sleeper: any AIBackoffSleeping = TaskAIBackoffSleeper(),
        clock: any AIMonotonicClock = SystemAIMonotonicClock(),
        logger: any AIEventLogging = NoOpAIEventLogger(),
        validator: StructuredSessionSummaryValidator = StructuredSessionSummaryValidator()
    ) {
        client = OpenRouterClient(
            keyProvider: keyProvider,
            configurationProvider: configurationProvider,
            transport: transport,
            sleeper: sleeper,
            clock: clock,
            logger: logger
        )
        self.validator = validator
    }

    init(
        client: OpenRouterClient,
        validator: StructuredSessionSummaryValidator = StructuredSessionSummaryValidator()
    ) {
        self.client = client
        self.validator = validator
    }

    func summarizeSession(_ input: StructuredSessionSummaryInput) async throws -> StructuredSessionSummaryResult {
        try validator.validateInput(input)
        let userContent = try encodedInput(input)
        let completion = try await client.complete(
            route: .organizer,
            taskInstructions: Self.taskInstructions(for: input.template),
            userContent: .string(userContent),
            schemaName: "structured_session_summary_\(input.template.rawValue)",
            schema: StructuredSessionSummarySchema.schema(for: input.template)
        )
        let payload = try decodePayload(completion.content)
        try validator.validate(payload, for: input)
        return StructuredSessionSummaryResult(
            template: payload.template,
            debriefTopics: payload.debriefTopics,
            sections: payload.sections,
            discussedTalkingPoints: payload.discussedTalkingPoints,
            metadata: completion.metadata
        )
    }

    private func encodedInput(_ input: StructuredSessionSummaryInput) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(input)
        } catch {
            throw AIProviderError.invalidInput
        }
        guard !data.isEmpty, data.count <= Self.maximumRequestBytes,
              let content = String(data: data, encoding: .utf8) else {
            throw AIProviderError.invalidInput
        }
        return content
    }

    private func decodePayload(_ data: Data) throws -> StructuredSessionSummaryPayload {
        guard !data.isEmpty else { throw AIProviderError.invalidResponse }
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  Set(object.keys) == Self.payloadKeys else {
                throw AIProviderError.invalidResponse
            }
            return try JSONDecoder().decode(StructuredSessionSummaryPayload.self, from: data)
        } catch let error as AIProviderError {
            throw error
        } catch {
            throw AIProviderError.invalidResponse
        }
    }

    private static func taskInstructions(for template: SessionSummaryTemplate) -> String {
        switch template {
        case .therapy:
            return """
            Create a patient-controlled therapy session debrief using only the supplied timestamped transcript. Return 3 to 5 concise debrief topics plus sections for main topics, patient realizations, provider observations, provider homework, candidate goals, beliefs or stuck points, coping tools, open questions, unfinished topics, and next-session items. Every item needs at least one verbatim citation with the source segment id and a timestamp inside that segment. Provider homework and provider-assigned goals need provider provenance and provider-spoken evidence. Discussed talking points are proposals only and must reference a supplied open talking point id. Preserve uncertainty. Do not diagnose, infer motives, prescribe, or claim that a proposal was saved or completed.
            """
        case .tms:
            return """
            Create a patient-controlled TMS session debrief using only the supplied timestamped transcript. Return 3 to 5 concise debrief topics plus sections for feelings before and after, distress or anxiety, provider-supplied triggers or provocations, questions for the provider, provider instructions, changes discussed, things to monitor, and next-session items. Every item needs at least one verbatim citation with the source segment id and a timestamp inside that segment. Provider instructions need provider provenance and provider-spoken evidence. Discussed talking points are proposals only and must reference a supplied open talking point id. Preserve uncertainty. Do not diagnose, prescribe, recommend stimulation or treatment changes, or claim that TMS caused any outcome.
            """
        }
    }

    private static let payloadKeys = Set([
        "template", "debriefTopics", "sections", "discussedTalkingPoints",
    ])
}

struct StructuredSessionSummaryPayload: Codable, Equatable, Sendable {
    let template: SessionSummaryTemplate
    let debriefTopics: [StructuredSessionSummaryItem]
    let sections: [StructuredSessionSummarySection]
    let discussedTalkingPoints: [StructuredSessionSummaryItem]
}

private enum StructuredSessionSummarySchema {
    static func schema(for template: SessionSummaryTemplate) -> JSONValue {
        object(
            properties: [
                "template": enumeration([template.rawValue]),
                "debriefTopics": array(item, maximum: 5, minimum: 3),
                "sections": array(section(for: template), maximum: 18),
                "discussedTalkingPoints": array(item, maximum: 64),
            ],
            required: ["template", "debriefTopics", "sections", "discussedTalkingPoints"]
        )
    }

    private static let citation = object(
        properties: [
            "sourceID": uuid,
            "quote": boundedString(2_000),
            "timestampMilliseconds": nullable(integer),
        ],
        required: ["sourceID", "quote", "timestampMilliseconds"]
    )

    private static let item = object(
        properties: [
            "id": uuid,
            "text": boundedString(8_000),
            "provenance": enumeration(["patient", "provider", "candyCorn"]),
            "evidence": array(citation, maximum: 8, minimum: 1),
            "relatedEntityID": nullable(uuid),
        ],
        required: ["id", "text", "provenance", "evidence", "relatedEntityID"]
    )

    private static func section(for template: SessionSummaryTemplate) -> JSONValue {
        object(
            properties: [
                "id": uuid,
                "kind": enumeration(allowedKinds(for: template).map(\.rawValue)),
                "title": boundedString(240),
                "items": array(item, maximum: 32),
            ],
            required: ["id", "kind", "title", "items"]
        )
    }

    private static func allowedKinds(for template: SessionSummaryTemplate) -> [SessionSummarySectionKind] {
        switch template {
        case .therapy:
            return [
                .mainTopics, .patientRealizations, .providerObservations, .homework, .goals,
                .beliefsOrStuckPoints, .copingTools, .questionsToRevisit, .unfinishedTopics,
                .nextSessionItems,
            ]
        case .tms:
            return [
                .currentFeelingsBeforeSession, .distressOrAnxiety, .triggersOrProvocations,
                .questionsForProvider, .providerInstructions, .changesDiscussed,
                .feelingsAfterSession, .thingsToMonitor, .nextSessionItems,
            ]
        }
    }

    private static let uuid: JSONValue = .object([
        "type": .string("string"),
        "format": .string("uuid"),
    ])
    private static let integer: JSONValue = .object(["type": .string("integer")])

    private static func boundedString(_ maximum: Int) -> JSONValue {
        .object([
            "type": .string("string"),
            "minLength": .number(1),
            "maxLength": .number(Double(maximum)),
        ])
    }

    private static func enumeration(_ values: [String]) -> JSONValue {
        .object([
            "type": .string("string"),
            "enum": .array(values.map(JSONValue.string)),
        ])
    }

    private static func nullable(_ value: JSONValue) -> JSONValue {
        .object(["anyOf": .array([value, .object(["type": .string("null")])])])
    }

    private static func array(_ items: JSONValue, maximum: Int, minimum: Int = 0) -> JSONValue {
        .object([
            "type": .string("array"),
            "items": items,
            "minItems": .number(Double(minimum)),
            "maxItems": .number(Double(maximum)),
        ])
    }

    private static func object(properties: [String: JSONValue], required: [String]) -> JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object(properties),
            "required": .array(required.map(JSONValue.string)),
            "additionalProperties": .bool(false),
        ])
    }
}
