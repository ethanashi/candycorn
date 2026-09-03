import Foundation
import Testing
@testable import CandyCorn

@Suite("Structured session summaries")
struct StructuredSessionSummaryTests {
    @Test("Therapy request uses organizer model, text-only input, and strict schema")
    func therapyRequestAndMetadata() async throws {
        let transport = SummaryFakeTransport([.response(Self.responseBody(payload: Self.therapyPayload))])
        let summarizer = makeSummarizer(transport: transport)

        let result = try await summarizer.summarizeSession(Self.therapyInput)

        #expect(summarizer.id == "openrouter-session-organizer")
        #expect(result.template == .therapy)
        #expect(result.metadata.provider == "openrouter")
        #expect(result.metadata.model == "configured/organizer")
        let request = try #require(await transport.requests.first)
        let body = try requestJSON(request)
        #expect(body["model"] as? String == "configured/organizer")
        let format = try #require(body["response_format"] as? [String: Any])
        let schemaWrapper = try #require(format["json_schema"] as? [String: Any])
        #expect(schemaWrapper["strict"] as? Bool == true)
        #expect(schemaWrapper["name"] as? String == "structured_session_summary_therapy")
        let schema = try #require(schemaWrapper["schema"] as? [String: Any])
        #expect(schema["additionalProperties"] as? Bool == false)
        let messages = try #require(body["messages"] as? [[String: Any]])
        let encodedInput = try #require(messages[2]["content"] as? String)
        #expect(encodedInput.contains("walking helped me settle"))
        #expect(!encodedInput.contains("audioURL"))
        #expect(!encodedInput.contains("file://"))
    }

    @Test("TMS uses its distinct section schema and accepts evidence-linked output")
    func validTMSPayload() async throws {
        let transport = SummaryFakeTransport([.response(Self.responseBody(payload: Self.tmsPayload))])
        let result = try await makeSummarizer(transport: transport).summarizeSession(Self.tmsInput)

        #expect(result.template == .tms)
        #expect(result.sections.map(\.kind) == [.currentFeelingsBeforeSession, .providerInstructions])
        let body = try requestJSON(try #require(await transport.requests.first))
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect((messages[1]["content"] as? String)?.contains("feelings before and after") == true)
        #expect((messages[1]["content"] as? String)?.contains("Do not diagnose") == true)
        let format = try #require(body["response_format"] as? [String: Any])
        let wrapper = try #require(format["json_schema"] as? [String: Any])
        let schema = try #require(wrapper["schema"] as? [String: Any])
        let properties = try #require(schema["properties"] as? [String: Any])
        let sections = try #require(properties["sections"] as? [String: Any])
        let section = try #require(sections["items"] as? [String: Any])
        let sectionProperties = try #require(section["properties"] as? [String: Any])
        let kind = try #require(sectionProperties["kind"] as? [String: Any])
        let kinds = try #require(kind["enum"] as? [String])
        #expect(kinds.contains("providerInstructions"))
        #expect(!kinds.contains("homework"))
    }

    @Test("Debrief requires three to five topics")
    func debriefTopicBounds() throws {
        let validator = StructuredSessionSummaryValidator()
        let two = Self.payload(topics: Array(Self.therapyPayload.debriefTopics.prefix(2)))
        let six = Self.payload(topics: Self.therapyPayload.debriefTopics + [
            Self.patientItem(id: Self.itemID6, text: "Walking helped me settle.", quote: "walking helped me settle"),
            Self.patientItem(id: Self.itemID7, text: "Walking helped me settle.", quote: "walking helped me settle"),
            Self.patientItem(id: Self.itemID8, text: "Walking helped me settle.", quote: "walking helped me settle"),
        ])

        #expect(throws: AIProviderError.invalidResponse) { try validator.validate(two, for: Self.therapyInput) }
        #expect(throws: AIProviderError.invalidResponse) { try validator.validate(six, for: Self.therapyInput) }
    }

    @Test("Citations require known source, verbatim quote, and in-range timestamp")
    func citationValidation() throws {
        let validator = StructuredSessionSummaryValidator()
        let base = Self.therapyPayload.debriefTopics[0]
        let missing = Self.replacingFirstTopic(Self.item(base, evidence: [
            EvidenceCitation(sourceID: Self.patientID, quote: "I think work has been hard", timestampMilliseconds: nil),
        ]))
        let outside = Self.replacingFirstTopic(Self.item(base, evidence: [
            EvidenceCitation(sourceID: Self.patientID, quote: "I think work has been hard", timestampMilliseconds: 5_001),
        ]))
        let fabricated = Self.replacingFirstTopic(Self.item(base, evidence: [
            EvidenceCitation(sourceID: Self.patientID, quote: "This never happened", timestampMilliseconds: 100),
        ]))
        let wrongSource = Self.replacingFirstTopic(Self.item(base, evidence: [
            EvidenceCitation(sourceID: UUID(), quote: "I think work has been hard", timestampMilliseconds: 100),
        ]))

        for payload in [missing, outside, fabricated, wrongSource] {
            #expect(throws: AIProviderError.invalidResponse) {
                try validator.validate(payload, for: Self.therapyInput)
            }
        }
    }

    @Test("Provider claims require provider provenance and provider-spoken evidence")
    func providerProvenance() throws {
        let validator = StructuredSessionSummaryValidator()
        let homework = try #require(Self.therapyPayload.sections.first)
        let providerItem = try #require(homework.items.first)
        let patientProvenance = Self.section(homework, items: [Self.item(providerItem, provenance: .patient)])
        let patientEvidence = Self.section(homework, items: [Self.item(providerItem, evidence: [
            EvidenceCitation(sourceID: Self.patientID, quote: "walking helped me settle", timestampMilliseconds: 1_000),
        ])])
        let unknownProvider = StructuredSessionSummaryItem(
            id: Self.itemID8,
            text: "The provider discussed sleep.",
            provenance: .provider,
            evidence: [EvidenceCitation(
                sourceID: Self.unknownID, quote: "We also discussed sleep.", timestampMilliseconds: 11_000
            )],
            relatedEntityID: nil
        )

        for section in [patientProvenance, patientEvidence] {
            #expect(throws: AIProviderError.invalidResponse) {
                try validator.validate(Self.payload(sections: [section]), for: Self.therapyInput)
            }
        }
        #expect(throws: AIProviderError.invalidResponse) {
            try validator.validate(Self.replacingFirstTopic(unknownProvider), for: Self.therapyInput)
        }
    }

    @Test("Discussed talking points must reference an open talking point")
    func talkingPointRelationship() throws {
        let item = try #require(Self.therapyPayload.discussedTalkingPoints.first)
        let stale = Self.item(item, relatedEntityID: UUID())
        let missing = StructuredSessionSummaryItem(
            id: item.id,
            text: item.text,
            provenance: item.provenance,
            evidence: item.evidence,
            relatedEntityID: nil
        )
        let validator = StructuredSessionSummaryValidator()

        for candidate in [stale, missing] {
            let payload = Self.payload(discussed: [candidate])
            #expect(throws: AIProviderError.invalidResponse) {
                try validator.validate(payload, for: Self.therapyInput)
            }
        }
    }

    @Test("Unsafe additions and removed uncertainty are rejected")
    func unsafeOutput() throws {
        let validator = StructuredSessionSummaryValidator()
        let first = Self.therapyPayload.debriefTopics[0]
        let unsafeTexts = [
            "Work has been hard.",
            "The patient has ADHD.",
            "The patient should stop taking medication.",
        ]
        for text in unsafeTexts {
            let payload = Self.replacingFirstTopic(Self.item(first, text: text))
            #expect(throws: AIProviderError.invalidResponse) {
                try validator.validate(payload, for: Self.therapyInput)
            }
        }

        let tmsCausation = Self.replacingFirstTopic(
            Self.item(first, text: "TMS improved my mood."), payload: Self.tmsPayload
        )
        let tmsAdvice = Self.replacingFirstTopic(
            Self.item(first, text: "Increase stimulation next time."), payload: Self.tmsPayload
        )
        #expect(throws: AIProviderError.invalidResponse) { try validator.validate(tmsCausation, for: Self.tmsInput) }
        #expect(throws: AIProviderError.invalidResponse) { try validator.validate(tmsAdvice, for: Self.tmsInput) }
    }

    @Test("Duplicate item and section identifiers are rejected")
    func duplicateIdentifiers() throws {
        let validator = StructuredSessionSummaryValidator()
        var topics = Self.therapyPayload.debriefTopics
        topics[1] = Self.item(topics[1], id: topics[0].id)
        let duplicateItems = Self.payload(topics: topics)
        let section = try #require(Self.therapyPayload.sections.first)
        let duplicateSections = Self.payload(sections: [section, section])

        #expect(throws: AIProviderError.invalidResponse) {
            try validator.validate(duplicateItems, for: Self.therapyInput)
        }
        #expect(throws: AIProviderError.invalidResponse) {
            try validator.validate(duplicateSections, for: Self.therapyInput)
        }
    }

    @Test("A section from the other template is rejected")
    func templateSectionMismatch() throws {
        let tmsSection = StructuredSessionSummarySection(
            id: Self.sectionID2,
            kind: .feelingsAfterSession,
            title: "After the session",
            items: []
        )

        #expect(throws: AIProviderError.invalidResponse) {
            try StructuredSessionSummaryValidator().validate(
                Self.payload(sections: [tmsSection]),
                for: Self.therapyInput
            )
        }
    }

    @Test("Invalid inputs fail before transport")
    func inputValidation() async {
        let duplicateSource = SessionTranscriptSource(
            id: Self.patientID, speaker: .provider, rawSpeakerLabel: "speaker-2",
            startMilliseconds: 5_000, endMilliseconds: 6_000, text: "Duplicate"
        )
        let invalidRange = SessionTranscriptSource(
            id: UUID(), speaker: .patient, rawSpeakerLabel: nil,
            startMilliseconds: 10, endMilliseconds: 10, text: "Invalid"
        )
        let inputs = [
            StructuredSessionSummaryInput(
                appointmentID: Self.appointmentID, template: .therapy,
                transcript: [], openTalkingPoints: []
            ),
            StructuredSessionSummaryInput(
                appointmentID: Self.appointmentID, template: .therapy,
                transcript: [Self.patientSource, duplicateSource], openTalkingPoints: []
            ),
            StructuredSessionSummaryInput(
                appointmentID: Self.appointmentID, template: .therapy,
                transcript: [invalidRange], openTalkingPoints: []
            ),
        ]

        for input in inputs {
            let transport = SummaryFakeTransport([])
            await #expect(throws: AIProviderError.invalidInput) {
                _ = try await makeSummarizer(transport: transport).summarizeSession(input)
            }
            #expect(await transport.requests.isEmpty)
        }
    }

    @Test("Malformed JSON fails, empty content retries once, and cancellation propagates")
    func transportEdgeCases() async throws {
        let malformed = SummaryFakeTransport([.response(Self.responseBody(content: "not-json"))])
        await #expect(throws: AIProviderError.invalidResponse) {
            _ = try await makeSummarizer(transport: malformed).summarizeSession(Self.therapyInput)
        }

        let retry = SummaryFakeTransport([
            .response(Self.responseBody(content: "   ")),
            .response(Self.responseBody(payload: Self.therapyPayload)),
        ])
        let sleeper = SummaryFakeSleeper()
        _ = try await makeSummarizer(transport: retry, sleeper: sleeper).summarizeSession(Self.therapyInput)
        #expect(await retry.requests.count == 2)
        #expect(await sleeper.durations == [.milliseconds(500)])

        let cancelled = SummaryFakeTransport([.failure(CancellationError())])
        await #expect(throws: CancellationError.self) {
            _ = try await makeSummarizer(transport: cancelled).summarizeSession(Self.therapyInput)
        }
        #expect(await cancelled.requests.count == 1)
    }

    private func makeSummarizer(
        transport: SummaryFakeTransport,
        sleeper: SummaryFakeSleeper = SummaryFakeSleeper()
    ) -> OpenRouterSessionSummarizer {
        OpenRouterSessionSummarizer(
            keyProvider: SummaryKeyProvider(),
            configurationProvider: SummaryConfigurationProvider(),
            transport: transport,
            sleeper: sleeper
        )
    }

    private func requestJSON(_ request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private static let appointmentID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private static let patientID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
    private static let providerID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
    private static let unknownID = UUID(uuidString: "20000000-0000-0000-0000-000000000003")!
    private static let talkingPointID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
    private static let itemID1 = UUID(uuidString: "40000000-0000-0000-0000-000000000001")!
    private static let itemID2 = UUID(uuidString: "40000000-0000-0000-0000-000000000002")!
    private static let itemID3 = UUID(uuidString: "40000000-0000-0000-0000-000000000003")!
    private static let itemID4 = UUID(uuidString: "40000000-0000-0000-0000-000000000004")!
    private static let itemID5 = UUID(uuidString: "40000000-0000-0000-0000-000000000005")!
    private static let itemID6 = UUID(uuidString: "40000000-0000-0000-0000-000000000006")!
    private static let itemID7 = UUID(uuidString: "40000000-0000-0000-0000-000000000007")!
    private static let itemID8 = UUID(uuidString: "40000000-0000-0000-0000-000000000008")!
    private static let sectionID1 = UUID(uuidString: "50000000-0000-0000-0000-000000000001")!
    private static let sectionID2 = UUID(uuidString: "50000000-0000-0000-0000-000000000002")!

    private static let patientSource = SessionTranscriptSource(
        id: patientID, speaker: .patient, rawSpeakerLabel: "speaker-1",
        startMilliseconds: 0, endMilliseconds: 5_000,
        text: "I think work has been hard, but walking helped me settle."
    )
    private static let providerSource = SessionTranscriptSource(
        id: providerID, speaker: .provider, rawSpeakerLabel: "speaker-2",
        startMilliseconds: 5_000, endMilliseconds: 10_000,
        text: "Please write down one thing that went well before our next session."
    )
    private static let unknownSource = SessionTranscriptSource(
        id: unknownID, speaker: .unknown, rawSpeakerLabel: "speaker-3",
        startMilliseconds: 10_000, endMilliseconds: 12_000,
        text: "We also discussed sleep."
    )
    private static let therapyInput = StructuredSessionSummaryInput(
        appointmentID: appointmentID,
        template: .therapy,
        transcript: [patientSource, providerSource, unknownSource],
        openTalkingPoints: [SessionTalkingPointSource(id: talkingPointID, text: "Work stress")]
    )
    private static let tmsInput = StructuredSessionSummaryInput(
        appointmentID: appointmentID,
        template: .tms,
        transcript: [patientSource, providerSource, unknownSource],
        openTalkingPoints: [SessionTalkingPointSource(id: talkingPointID, text: "Work stress")]
    )

    private static let therapyPayload = StructuredSessionSummaryPayload(
        template: .therapy,
        debriefTopics: baseTopics,
        sections: [StructuredSessionSummarySection(
            id: sectionID1,
            kind: .homework,
            title: "What your provider asked you to do",
            items: [providerItem(
                id: itemID4,
                text: "Write down one thing that went well before the next session."
            )]
        )],
        discussedTalkingPoints: [patientItem(
            id: itemID5,
            text: "I think work stress was discussed.",
            quote: "I think work has been hard",
            relatedEntityID: talkingPointID
        )]
    )

    private static let tmsPayload = StructuredSessionSummaryPayload(
        template: .tms,
        debriefTopics: baseTopics,
        sections: [
            StructuredSessionSummarySection(
                id: sectionID1,
                kind: .currentFeelingsBeforeSession,
                title: "Before the session",
                items: [patientItem(
                    id: itemID6, text: "I think work has been hard.", quote: "I think work has been hard"
                )]
            ),
            StructuredSessionSummarySection(
                id: sectionID2,
                kind: .providerInstructions,
                title: "Provider instructions",
                items: [providerItem(
                    id: itemID7, text: "Write down one thing that went well before the next session."
                )]
            ),
        ],
        discussedTalkingPoints: [patientItem(
            id: itemID5,
            text: "I think work stress was discussed.",
            quote: "I think work has been hard",
            relatedEntityID: talkingPointID
        )]
    )

    private static let baseTopics = [
        patientItem(id: itemID1, text: "I think work has been hard.", quote: "I think work has been hard"),
        patientItem(id: itemID2, text: "Walking helped me settle.", quote: "walking helped me settle"),
        providerItem(id: itemID3, text: "The provider asked me to write one thing down."),
    ]

    private static func patientItem(
        id: UUID,
        text: String,
        quote: String,
        relatedEntityID: UUID? = nil
    ) -> StructuredSessionSummaryItem {
        StructuredSessionSummaryItem(
            id: id,
            text: text,
            provenance: .patient,
            evidence: [EvidenceCitation(sourceID: patientID, quote: quote, timestampMilliseconds: 1_000)],
            relatedEntityID: relatedEntityID
        )
    }

    private static func providerItem(id: UUID, text: String) -> StructuredSessionSummaryItem {
        StructuredSessionSummaryItem(
            id: id,
            text: text,
            provenance: .provider,
            evidence: [EvidenceCitation(
                sourceID: providerID,
                quote: "Please write down one thing that went well before our next session.",
                timestampMilliseconds: 6_000
            )],
            relatedEntityID: nil
        )
    }

    private static func item(
        _ original: StructuredSessionSummaryItem,
        id: UUID? = nil,
        text: String? = nil,
        provenance: SessionSummaryItemProvenance? = nil,
        evidence: [EvidenceCitation]? = nil,
        relatedEntityID: UUID?? = nil
    ) -> StructuredSessionSummaryItem {
        StructuredSessionSummaryItem(
            id: id ?? original.id,
            text: text ?? original.text,
            provenance: provenance ?? original.provenance,
            evidence: evidence ?? original.evidence,
            relatedEntityID: relatedEntityID ?? original.relatedEntityID
        )
    }

    private static func section(
        _ original: StructuredSessionSummarySection,
        items: [StructuredSessionSummaryItem]
    ) -> StructuredSessionSummarySection {
        StructuredSessionSummarySection(id: original.id, kind: original.kind, title: original.title, items: items)
    }

    private static func payload(
        topics: [StructuredSessionSummaryItem] = therapyPayload.debriefTopics,
        sections: [StructuredSessionSummarySection] = therapyPayload.sections,
        discussed: [StructuredSessionSummaryItem] = therapyPayload.discussedTalkingPoints
    ) -> StructuredSessionSummaryPayload {
        StructuredSessionSummaryPayload(
            template: .therapy,
            debriefTopics: topics,
            sections: sections,
            discussedTalkingPoints: discussed
        )
    }

    private static func replacingFirstTopic(
        _ item: StructuredSessionSummaryItem,
        payload: StructuredSessionSummaryPayload = therapyPayload
    ) -> StructuredSessionSummaryPayload {
        var topics = payload.debriefTopics
        topics[0] = item
        return StructuredSessionSummaryPayload(
            template: payload.template,
            debriefTopics: topics,
            sections: payload.sections,
            discussedTalkingPoints: payload.discussedTalkingPoints
        )
    }

    private static func responseBody(payload: StructuredSessionSummaryPayload) -> Data {
        let content = (try? String(data: JSONEncoder().encode(payload), encoding: .utf8)) ?? ""
        return responseBody(content: content)
    }

    private static func responseBody(content: String) -> Data {
        let object: [String: Any] = [
            "model": "configured/organizer",
            "choices": [["message": ["content": content], "finish_reason": "stop"]],
            "usage": ["prompt_tokens": 10, "completion_tokens": 20, "total_tokens": 30],
        ]
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
    }
}

private final class SummaryKeyProvider: OpenRouterAPIKeyProviding, @unchecked Sendable {
    func readKey() throws -> String? { "test-key" }
    func storeKey(_ value: String) throws { _ = value }
    func removeKey() throws {}
    func hasKey() throws -> Bool { true }
}

private final class SummaryConfigurationProvider: AIConfigurationProviding, @unchecked Sendable {
    func load() -> AIModelConfiguration {
        AIModelConfiguration(organizerModelID: "configured/organizer", visionModelID: "configured/vision")
    }
    func save(_ configuration: AIModelConfiguration) throws { _ = configuration }
    func reset() throws {}
}

private actor SummaryFakeTransport: AIHTTPTransport {
    enum Outcome: @unchecked Sendable {
        case response(Data)
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
        case let .response(data):
            let response = HTTPURLResponse(
                url: try #require(request.url), statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil
            )
            return (data, try #require(response))
        case let .failure(error):
            throw error
        }
    }
}

private actor SummaryFakeSleeper: AIBackoffSleeping {
    private(set) var durations: [Duration] = []

    func sleep(for duration: Duration) async throws {
        try Task.checkCancellation()
        durations.append(duration)
    }
}
