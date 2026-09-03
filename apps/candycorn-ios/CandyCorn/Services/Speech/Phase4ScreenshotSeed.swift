import Foundation

enum Phase4ScreenshotSeed {
    private static let therapyPath = "/sessions/therapy-sep-2"
    private static let debriefPath = "/sessions/therapy-sep-2/debrief"
    private static let summaryID = uuid("8F000000-0000-0000-0000-000000000001")
    private static let processingID = uuid("8F000000-0000-0000-0000-000000000002")
    private static let timestamp = Date(timeIntervalSince1970: 1_788_654_600)

    static func applyingIfNeeded(to source: CareSnapshot, arguments: [String]) -> CareSnapshot {
        guard let flag = arguments.firstIndex(of: "-screen") else { return source }
        let valueIndex = arguments.index(after: flag)
        guard valueIndex < arguments.endIndex,
              arguments[valueIndex] == therapyPath || arguments[valueIndex] == debriefPath else { return source }
        var snapshot = source
        guard let appointmentIndex = snapshot.appointments.firstIndex(where: { $0.id == SeededData.therapySessionID }),
              let attachmentID = snapshot.appointments[appointmentIndex].recordingAttachmentID else { return source }
        let transcript = snapshot.transcript.filter { $0.appointmentID == SeededData.therapySessionID }
        guard transcript.count >= 3 else { return source }
        let result = summary(transcript: transcript)
        guard let payload = try? PersistenceCoding.encode(result) else { return source }
        let artifact = AIArtifact(
            id: summaryID, kind: .sessionSummary,
            sourceIDs: [SeededData.therapySessionID, attachmentID] + transcript.map(\.id),
            provider: result.metadata.provider, model: result.metadata.model,
            structuredPayload: payload, createdAt: timestamp
        )
        upsert(artifact, in: &snapshot.artifacts)
        snapshot.appointments[appointmentIndex].summaryID = summaryID
        snapshot.appointments[appointmentIndex].status = .completed
        let processing = SessionProcessingRecord(
            id: processingID, appointmentID: SeededData.therapySessionID,
            stage: .ready, progress: 1, summaryConsentGranted: true,
            failure: nil, updatedAt: timestamp
        )
        upsertProcessing(processing, in: &snapshot.sessionProcessing)
        return snapshot
    }

    private static func summary(transcript: [TranscriptSegment]) -> StructuredSessionSummaryResult {
        let first = transcript[0]
        let second = transcript[1]
        let third = transcript[2]
        let topics = [
            item("8F100000-0000-0000-0000-000000000001", "The missed chance to prove you could play still feels unresolved.", .patient, first),
            item("8F100000-0000-0000-0000-000000000002", "You separated missing football from missing the chance to test yourself.", .provider, second),
            item("8F100000-0000-0000-0000-000000000003", "The meeting with the coaches is still worth revisiting.", .candyCorn, third),
        ]
        let homework = StructuredSessionSummarySection(
            id: uuid("8F200000-0000-0000-0000-000000000001"), kind: .homework,
            title: "What your provider asked you to do",
            items: [item("8F210000-0000-0000-0000-000000000001", "Finish the senior-year football timeline.", .provider, second)]
        )
        let goals = StructuredSessionSummarySection(
            id: uuid("8F200000-0000-0000-0000-000000000002"), kind: .goals,
            title: "Things that sounded like goals",
            items: [item("8F210000-0000-0000-0000-000000000002", "Notice when guilt follows a few hours of relief.", .patient, first)]
        )
        let questions = StructuredSessionSummarySection(
            id: uuid("8F200000-0000-0000-0000-000000000003"), kind: .questionsToRevisit,
            title: "Questions left open",
            items: [item("8F210000-0000-0000-0000-000000000003", "What would proving yourself have changed?", .candyCorn, third)]
        )
        return StructuredSessionSummaryResult(
            template: .therapy, debriefTopics: topics,
            sections: [homework, goals, questions], discussedTalkingPoints: [],
            metadata: AIResultMetadata(
                provider: "screenshot", model: "deterministic-session-debrief",
                usage: AIUsage(promptTokens: nil, completionTokens: nil, reasoningTokens: nil, totalTokens: nil, costCredits: nil)
            )
        )
    }

    private static func item(
        _ id: String,
        _ text: String,
        _ provenance: SessionSummaryItemProvenance,
        _ segment: TranscriptSegment
    ) -> StructuredSessionSummaryItem {
        StructuredSessionSummaryItem(
            id: uuid(id), text: text, provenance: provenance,
            evidence: [EvidenceCitation(
                sourceID: segment.id, quote: segment.text,
                timestampMilliseconds: segment.startMilliseconds
            )], relatedEntityID: nil
        )
    }

    private static func upsert(_ value: AIArtifact, in values: inout [AIArtifact]) {
        values.removeAll { $0.id == value.id }
        values.append(value)
    }

    private static func upsertProcessing(_ value: SessionProcessingRecord, in values: inout [SessionProcessingRecord]) {
        values.removeAll { $0.appointmentID == value.appointmentID }
        values.append(value)
    }

    private static func uuid(_ value: String) -> UUID {
        guard let id = UUID(uuidString: value) else { preconditionFailure("Fixed screenshot UUID must be valid") }
        return id
    }
}
