import Foundation

actor OpenRouterLanguageModel: CandyCornLanguageModel {
    nonisolated let id = OpenRouterClient.providerID
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

    func rewriteJournal(_ input: RewriteJournalInput) async throws -> RewriteJournalResult {
        try validator.validateInputSources([input.source])
        let completion = try await request(
            input,
            task: "Rewrite the journal in first person without changing meaning. Preserve chronology, uncertainty, names, and explicit language when preserveExplicitLanguage is true. Split the result into evidence-backed segments and list unclear areas without guessing.",
            schemaName: "journal_rewrite",
            schema: OpenRouterSchemas.rewrite
        )
        let payload: RewritePayload = try decode(completion.content)
        try validator.validateRewrite(payload.segments, unclearAreas: payload.unclearAreas, source: input.source)
        return RewriteJournalResult(segments: payload.segments, unclearAreas: payload.unclearAreas, metadata: completion.metadata)
    }

    func summarizeJournal(_ input: JournalSummaryInput) async throws -> JournalSummaryResult {
        try validator.validateInputSources([input.source])
        let completion = try await request(
            input,
            task: "Summarize only what the journal says. Return compact evidence-backed statements. Preserve uncertainty and do not interpret causes or motives.",
            schemaName: "journal_summary",
            schema: OpenRouterSchemas.statementList
        )
        let payload: StatementListPayload = try decode(completion.content)
        try validator.validateSummary(payload.statements, sources: [input.source])
        return JournalSummaryResult(statements: payload.statements, metadata: completion.metadata)
    }

    func extractJournalSignals(_ input: JournalSignalInput) async throws -> JournalSignalResult {
        try validator.validateInputSources([input.source])
        let completion = try await request(
            input,
            task: "Extract emotions, possible themes, explicit commitments, and optional talking-point suggestions. A commitment requires direct commitment language. Never turn maybe, might, could, or should into a commitment. Every evidence field must be an exact source quote.",
            schemaName: "journal_signals",
            schema: OpenRouterSchemas.journalSignals
        )
        let signals: JournalSignals = try decode(completion.content)
        try validator.validateSignals(signals, source: input.source)
        return JournalSignalResult(signals: signals, metadata: completion.metadata)
    }

    func summarizeSession(_ input: SessionSummaryInput) async throws -> SessionSummaryResult {
        try validator.validateInputSources([input.manualNotes])
        let completion = try await request(
            input,
            task: "Organize the manually typed session notes into titled sections. Use only the manual notes supplied. Every statement must cite an exact quote and its known source id.",
            schemaName: "session_summary",
            schema: OpenRouterSchemas.sessionSummary
        )
        let payload: SessionPayload = try decode(completion.content)
        try validator.validateSession(payload.sections, source: input.manualNotes)
        return SessionSummaryResult(sections: payload.sections, metadata: completion.metadata)
    }

    func generateAppointmentBrief(_ input: AppointmentBriefInput) async throws -> AppointmentBriefResult {
        guard input.appointmentKind == input.contextPacket.request.appointmentKind else {
            throw AIProviderError.invalidInput
        }
        try validator.validateInputSources(input.sources)
        guard !input.contextPacket.text.isEmpty,
              input.contextPacket.text.count <= ContextPacketLimits.appointment.maximumCharacters else {
            throw AIProviderError.invalidInput
        }
        let completion = try await client.complete(
            route: .organizer,
            taskInstructions: "Create an editable appointment brief grouped into useful titled sections. Include only supplied facts. Every statement must cite an exact quote and known source id. Provider homework remains provider homework.",
            userContent: .string(input.contextPacket.text),
            schemaName: "appointment_brief",
            schema: OpenRouterSchemas.appointmentBrief
        )
        let payload: BriefPayload = try decode(completion.content)
        try validator.validateBrief(payload.sections, sources: input.sources)
        let result = AppointmentBriefResult(sections: payload.sections, userEditedAt: nil, metadata: completion.metadata)
        guard input.appointmentKind != .tms || AppointmentBriefSafety.isSafeForTMS(result) else {
            throw AIProviderError.invalidResponse
        }
        return result
    }

    private func request<T: Encodable & Sendable>(
        _ input: T,
        task: String,
        schemaName: String,
        schema: JSONValue
    ) async throws -> OpenRouterCompletionResult {
        let content = try encodedUserData(input)
        return try await client.complete(
            route: .organizer,
            taskInstructions: task,
            userContent: .string(content),
            schemaName: schemaName,
            schema: schema
        )
    }

    private func encodedUserData<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        guard !data.isEmpty, data.count <= 262_144, let string = String(data: data, encoding: .utf8) else {
            throw AIProviderError.invalidInput
        }
        return string
    }

    private func decode<T: Decodable>(_ data: Data, as type: T.Type = T.self) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw AIProviderError.invalidResponse
        }
    }
}

private struct RewritePayload: Codable {
    let segments: [RewriteSegment]
    let unclearAreas: [String]
}

private struct StatementListPayload: Codable { let statements: [EvidenceBackedStatement] }
private struct SessionPayload: Codable { let sections: [SessionSummarySection] }
private struct BriefPayload: Codable { let sections: [AppointmentBriefSection] }

enum OpenRouterSchemas {
    static let citation = object(
        properties: [
            "sourceID": uuid,
            "quote": boundedString(2_000),
            "timestampMilliseconds": nullable(integer),
        ],
        required: ["sourceID", "quote", "timestampMilliseconds"]
    )

    static let statement = object(
        properties: [
            "id": uuid,
            "text": boundedString(8_000),
            "evidence": array(citation, maximum: 8, minimum: 1),
        ],
        required: ["id", "text", "evidence"]
    )

    static let rewrite = object(
        properties: [
            "segments": array(object(
                properties: ["id": uuid, "text": boundedString(8_000), "evidence": array(citation, maximum: 8, minimum: 1)],
                required: ["id", "text", "evidence"]
            ), maximum: 32, minimum: 1),
            "unclearAreas": array(boundedString(1_000), maximum: 32),
        ],
        required: ["segments", "unclearAreas"]
    )

    static let statementList = object(
        properties: ["statements": array(statement, maximum: 32, minimum: 1)],
        required: ["statements"]
    )

    static let journalSignals = object(
        properties: [
            "summary": boundedString(8_000),
            "emotions": array(evidenceItem, maximum: 32),
            "explicitCommitments": array(commitment, maximum: 32),
            "talkingPointSuggestions": array(talkingPoint, maximum: 32),
            "possibleThemes": array(evidenceItem, maximum: 32),
        ],
        required: ["summary", "emotions", "explicitCommitments", "talkingPointSuggestions", "possibleThemes"]
    )

    static let sessionSummary = object(
        properties: ["sections": array(section, maximum: 32, minimum: 1)],
        required: ["sections"]
    )

    static let appointmentBrief = sessionSummary

    static let vision = object(
        properties: [
            "text": boundedString(8_000),
            "uncertainSpans": array(boundedString(2_000), maximum: 32),
        ],
        required: ["text", "uncertainSpans"]
    )

    private static let evidenceItem = object(
        properties: ["label": boundedString(1_000), "evidence": boundedString(2_000)],
        required: ["label", "evidence"]
    )
    private static let commitment = object(
        properties: [
            "id": uuid,
            "text": boundedString(8_000),
            "cadenceHint": nullable(boundedString(240)),
            "evidence": boundedString(2_000),
        ],
        required: ["id", "text", "cadenceHint", "evidence"]
    )
    private static let talkingPoint = object(
        properties: [
            "id": uuid,
            "text": boundedString(8_000),
            "reason": boundedString(8_000),
            "evidence": boundedString(2_000),
        ],
        required: ["id", "text", "reason", "evidence"]
    )
    private static let section = object(
        properties: [
            "id": uuid,
            "title": boundedString(240),
            "statements": array(statement, maximum: 32, minimum: 1),
        ],
        required: ["id", "title", "statements"]
    )
    private static let uuid: JSONValue = .object(["type": .string("string"), "format": .string("uuid")])
    private static let integer: JSONValue = .object(["type": .string("integer")])

    private static func boundedString(_ maximum: Int) -> JSONValue {
        .object(["type": .string("string"), "minLength": .number(1), "maxLength": .number(Double(maximum))])
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
