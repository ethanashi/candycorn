import Foundation
import Testing
@testable import CandyCorn

@Suite("OpenRouter provider")
struct OpenRouterProviderTests {
    @Test("Structured request uses configured model, privacy headers, and strict budget")
    func requestShapeAndUsage() async throws {
        let logger = CapturingAIEventLogger()
        let transport = FakeAITransport([.response(
            status: 200,
            body: Self.responseBody(content: Self.statementContent, model: "configured/organizer", usage: true)
        )])
        let model = makeLanguageModel(transport: transport, configuration: .init(
            organizerModelID: "configured/organizer",
            visionModelID: "configured/vision"
        ), logger: logger)
        let result = try await model.summarizeJournal(.init(source: Self.journal))
        #expect(result.metadata.model == "configured/organizer")
        #expect(result.metadata.usage.promptTokens == 21)
        #expect(result.metadata.usage.completionTokens == 13)
        #expect(result.metadata.usage.reasoningTokens == 5)
        #expect(result.metadata.usage.totalTokens == 34)
        #expect(result.metadata.usage.costCredits == 0.00042)
        let logged = try #require(logger.snapshot().last)
        #expect(logged.attemptCount == 1)
        #expect(logged.reasoningTokens == 5)
        #expect(logged.costCredits == 0.00042)
        #expect(logged.success)

        let request = try #require(await transport.requests.first)
        #expect(request.url?.absoluteString == "https://openrouter.ai/api/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
        #expect(request.value(forHTTPHeaderField: "HTTP-Referer") == "https://github.com/ethanashi/candycorn")
        #expect(request.value(forHTTPHeaderField: "X-Title") == "Candy Corn")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.timeoutInterval == 45)
        let body = try requestJSON(request)
        #expect(body["model"] as? String == "configured/organizer")
        #expect(body["max_tokens"] as? Int == 2_400)
        #expect(body["stream"] as? Bool == false)
        #expect(body["temperature"] as? Double == 0.1)
        #expect((body["reasoning"] as? [String: Any])?["effort"] as? String == "low")
        #expect((body["provider"] as? [String: Any])?["require_parameters"] as? Bool == true)
        let format = try #require(body["response_format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        let jsonSchema = try #require(format["json_schema"] as? [String: Any])
        #expect(jsonSchema["strict"] as? Bool == true)
        #expect((jsonSchema["schema"] as? [String: Any])?["additionalProperties"] as? Bool == false)
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.count == 3)
        #expect(messages[0]["role"] as? String == "system")
        #expect((messages[0]["content"] as? String)?.contains("untrusted data") == true)
        #expect(messages[1]["role"] as? String == "system")
        let userJSON = try #require(messages[2]["content"] as? String)
        #expect((try JSONSerialization.jsonObject(with: Data(userJSON.utf8)) as? [String: Any]) != nil)
    }

    @Test("Empty stop and transient responses retry within the three-attempt bound")
    func retryPolicy() async throws {
        let emptyTransport = FakeAITransport([
            .response(status: 200, body: Self.responseBody(content: "   ", finishReason: "stop")),
            .response(status: 200, body: Self.responseBody(content: Self.statementContent)),
        ])
        let emptySleeper = FakeAISleeper()
        _ = try await makeLanguageModel(transport: emptyTransport, sleeper: emptySleeper)
            .summarizeJournal(.init(source: Self.journal))
        #expect(await emptyTransport.requests.count == 2)
        #expect(await emptySleeper.durations == [.milliseconds(500)])

        let transientTransport = FakeAITransport([
            .response(status: 503, body: Data()),
            .failure(URLError(.timedOut)),
            .response(status: 200, body: Self.responseBody(content: Self.statementContent)),
        ])
        let transientSleeper = FakeAISleeper()
        _ = try await makeLanguageModel(transport: transientTransport, sleeper: transientSleeper)
            .summarizeJournal(.init(source: Self.journal))
        #expect(await transientTransport.requests.count == 3)
        #expect(await transientSleeper.durations == [.milliseconds(500), .milliseconds(1_000)])

        let limitedTransport = FakeAITransport([
            .response(status: 429, body: Data(), headers: ["Retry-After": "10"]),
            .response(status: 200, body: Self.responseBody(content: Self.statementContent)),
        ])
        let limitedSleeper = FakeAISleeper()
        _ = try await makeLanguageModel(transport: limitedTransport, sleeper: limitedSleeper)
            .summarizeJournal(.init(source: Self.journal))
        #expect(await limitedTransport.requests.count == 2)
        #expect(await limitedSleeper.durations == [.seconds(5)])
    }

    @Test("Cancellation and unauthorized responses do not retry")
    func terminalFailures() async {
        let cancelled = FakeAITransport([.failure(CancellationError())])
        await #expect(throws: CancellationError.self) {
            _ = try await makeLanguageModel(transport: cancelled).summarizeJournal(.init(source: Self.journal))
        }
        #expect(await cancelled.requests.count == 1)

        let unauthorized = FakeAITransport([.response(status: 401, body: Data("secret body".utf8))])
        await #expect(throws: AIProviderError.unauthorized) {
            _ = try await makeLanguageModel(transport: unauthorized).summarizeJournal(.init(source: Self.journal))
        }
        #expect(await unauthorized.requests.count == 1)
    }

    @Test("Journal rewrite, signals, session, and brief payloads decode")
    func languagePayloadsDecode() async throws {
        let source = Self.journal
        let transport = FakeAITransport([
            .response(status: 200, body: Self.responseBody(content: Self.rewriteContent)),
            .response(status: 200, body: Self.responseBody(content: Self.signalsContent)),
            .response(status: 200, body: Self.responseBody(content: Self.sessionContent)),
            .response(status: 200, body: Self.responseBody(content: Self.briefContent)),
        ])
        let model = makeLanguageModel(transport: transport)
        let rewrite = try await model.rewriteJournal(.init(source: source, preserveExplicitLanguage: true))
        #expect(rewrite.segments.first?.text.contains("not sure") == true)
        let signals = try await model.extractJournalSignals(.init(source: source))
        #expect(signals.signals.explicitCommitments.count == 1)
        let session = try await model.summarizeSession(.init(appointmentID: UUID(), appointmentKind: .therapy, manualNotes: source))
        #expect(session.sections.first?.title == "What happened")
        let brief = try await model.generateAppointmentBrief(.init(appointmentKind: .therapy, sources: [source]))
        #expect(brief.sections.first?.statements.count == 1)
        #expect(await transport.requests.count == 4)
    }

    @Test("Vision uses configured model and a base64 image part")
    func visionPayload() async throws {
        let transport = FakeAITransport([.response(
            status: 200,
            body: Self.responseBody(content: #"{"text":"handwritten line [?]","uncertainSpans":["[?]"]}"#, model: "configured/vision")
        )])
        let reader = OpenRouterVisionReader(
            keyProvider: FixedAPIKeyProvider(),
            configurationProvider: FixedAIConfiguration(.init(
                organizerModelID: "configured/organizer",
                visionModelID: "configured/vision"
            )),
            transport: transport
        )
        let result = try await reader.extractText(from: .init(
            journalID: UUID(), attachmentID: UUID(), mediaType: "image/jpeg", imageData: Data([0xff, 0xd8, 0xff])
        ))
        #expect(result.text == "handwritten line [?]")
        let body = try requestJSON(try #require(await transport.requests.first))
        #expect(body["model"] as? String == "configured/vision")
        let messages = try #require(body["messages"] as? [[String: Any]])
        let parts = try #require(messages[2]["content"] as? [[String: Any]])
        #expect(parts.count == 2)
        #expect(parts[0]["type"] as? String == "text")
        #expect(parts[1]["type"] as? String == "image_url")
        let imageURL = (parts[1]["image_url"] as? [String: Any])?["url"] as? String
        #expect(imageURL?.hasPrefix("data:image/jpeg;base64,") == true)
    }

    @Test("Malformed output, missing keys, and invalid images fail locally")
    func invalidInputs() async {
        let malformed = FakeAITransport([.response(status: 200, body: Self.responseBody(content: "not-json"))])
        await #expect(throws: AIProviderError.invalidResponse) {
            _ = try await makeLanguageModel(transport: malformed).summarizeJournal(.init(source: Self.journal))
        }
        let missingKeyTransport = FakeAITransport([])
        let missingKeyModel = OpenRouterLanguageModel(
            keyProvider: FixedAPIKeyProvider(key: "  "),
            configurationProvider: FixedAIConfiguration(.defaults),
            transport: missingKeyTransport
        )
        await #expect(throws: AIProviderError.missingKey) {
            _ = try await missingKeyModel.summarizeJournal(.init(source: Self.journal))
        }
        #expect(await missingKeyTransport.requests.isEmpty)

        let reader = OpenRouterVisionReader(
            keyProvider: FixedAPIKeyProvider(),
            configurationProvider: FixedAIConfiguration(.defaults),
            transport: FakeAITransport([])
        )
        await #expect(throws: AIProviderError.invalidInput) {
            _ = try await reader.extractText(from: .init(
                journalID: UUID(), attachmentID: UUID(), mediaType: "text/plain", imageData: Data()
            ))
        }
    }

    @Test("Empty choices, no-content success, and oversized bodies are rejected")
    func unusableResponses() async {
        let emptyChoices = FakeAITransport([.response(
            status: 200,
            body: Data(#"{"choices":[]}"#.utf8)
        )])
        await #expect(throws: AIProviderError.invalidResponse) {
            _ = try await makeLanguageModel(transport: emptyChoices).summarizeJournal(.init(source: Self.journal))
        }
        #expect(await emptyChoices.requests.count == 1)

        let noContent = FakeAITransport([.response(status: 204, body: Data())])
        await #expect(throws: AIProviderError.invalidResponse) {
            _ = try await makeLanguageModel(transport: noContent).summarizeJournal(.init(source: Self.journal))
        }
        #expect(await noContent.requests.count == 1)

        let oversized = FakeAITransport([.response(
            status: 200,
            body: Data(repeating: 0x61, count: 1_048_577)
        )])
        await #expect(throws: AIProviderError.responseTooLarge) {
            _ = try await makeLanguageModel(transport: oversized).summarizeJournal(.init(source: Self.journal))
        }
        #expect(await oversized.requests.count == 1)
    }

    private func makeLanguageModel(
        transport: FakeAITransport,
        configuration: AIModelConfiguration = .defaults,
        sleeper: FakeAISleeper = FakeAISleeper(),
        logger: any AIEventLogging = NoOpAIEventLogger()
    ) -> OpenRouterLanguageModel {
        OpenRouterLanguageModel(
            keyProvider: FixedAPIKeyProvider(),
            configurationProvider: FixedAIConfiguration(configuration),
            transport: transport,
            sleeper: sleeper,
            logger: logger
        )
    }

    private func requestJSON(_ request: URLRequest) throws -> [String: Any] {
        let body = try #require(request.httpBody)
        return try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    private static let sourceID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa") ?? UUID()
    private static let journal = SourceTextDocument(
        id: sourceID,
        kind: .journal,
        title: "Test journal",
        text: "I am not sure why I felt guilty. I'm going to walk for 10 minutes tomorrow.",
        occurredAt: Date(timeIntervalSince1970: 1)
    )
    private static let statementContent = #"{"statements":[{"id":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","text":"I am not sure why I felt guilty.","evidence":[{"sourceID":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","quote":"I am not sure why I felt guilty.","timestampMilliseconds":null}]}]}"#
    private static let rewriteContent = #"{"segments":[{"id":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","text":"I am not sure why I felt guilty.","evidence":[{"sourceID":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","quote":"I am not sure why I felt guilty.","timestampMilliseconds":null}]}],"unclearAreas":[]}"#
    private static let signalsContent = #"{"summary":"The journal describes guilt and a plan to walk.","emotions":[{"label":"Guilt","evidence":"felt guilty"}],"explicitCommitments":[{"id":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","text":"Walk for 10 minutes tomorrow.","cadenceHint":"one-off","evidence":"I'm going to walk for 10 minutes tomorrow."}],"talkingPointSuggestions":[{"id":"cccccccc-cccc-cccc-cccc-cccccccccccc","text":"Bring up the guilt.","reason":"The journal names guilt.","evidence":"felt guilty"}],"possibleThemes":[{"label":"Guilt","evidence":"felt guilty"}]}"#
    private static let sessionContent = #"{"sections":[{"id":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","title":"What happened","statements":[{"id":"cccccccc-cccc-cccc-cccc-cccccccccccc","text":"I am not sure why I felt guilty.","evidence":[{"sourceID":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","quote":"I am not sure why I felt guilty.","timestampMilliseconds":null}]}]}]}"#
    private static let briefContent = sessionContent

    private static func responseBody(
        content: String,
        finishReason: String = "stop",
        model: String = "test/model",
        usage: Bool = false
    ) -> Data {
        var object: [String: Any] = [
            "model": model,
            "choices": [["message": ["content": content], "finish_reason": finishReason]],
        ]
        if usage {
            object["usage"] = [
                "prompt_tokens": 21,
                "completion_tokens": 13,
                "total_tokens": 34,
                "cost": 0.00042,
                "completion_tokens_details": ["reasoning_tokens": 5],
            ]
        }
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
    }
}

private final class FixedAPIKeyProvider: OpenRouterAPIKeyProviding, @unchecked Sendable {
    private let key: String?
    init(key: String? = "test-key") { self.key = key }
    func readKey() throws -> String? { key }
    func storeKey(_ value: String) throws { _ = value }
    func removeKey() throws {}
    func hasKey() throws -> Bool { key?.isEmpty == false }
}

private final class FixedAIConfiguration: AIConfigurationProviding, @unchecked Sendable {
    private let configuration: AIModelConfiguration
    init(_ configuration: AIModelConfiguration) { self.configuration = configuration }
    func load() -> AIModelConfiguration { configuration }
    func save(_ configuration: AIModelConfiguration) throws { _ = configuration }
    func reset() throws {}
}

private actor FakeAITransport: AIHTTPTransport {
    enum Outcome: @unchecked Sendable {
        case response(status: Int, body: Data, headers: [String: String] = [:])
        case failure(Error)
    }

    private var outcomes: [Outcome]
    private(set) var requests: [URLRequest] = []

    init(_ outcomes: [Outcome]) { self.outcomes = outcomes }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !outcomes.isEmpty else { throw URLError(.badServerResponse) }
        let outcome = outcomes.removeFirst()
        switch outcome {
        case let .failure(error): throw error
        case let .response(status, body, headers):
            let response = HTTPURLResponse(
                url: try #require(request.url), statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers
            )
            return (body, try #require(response))
        }
    }
}

private actor FakeAISleeper: AIBackoffSleeping {
    private(set) var durations: [Duration] = []
    func sleep(for duration: Duration) async throws {
        try Task.checkCancellation()
        durations.append(duration)
    }
}

private final class CapturingAIEventLogger: AIEventLogging, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [AIEventMetrics] = []

    func record(_ name: AIEventName, metrics: AIEventMetrics) {
        guard name == .requestCompleted else { return }
        lock.lock()
        values.append(metrics)
        lock.unlock()
    }

    func snapshot() -> [AIEventMetrics] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}
