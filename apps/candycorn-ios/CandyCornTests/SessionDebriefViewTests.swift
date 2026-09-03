import Foundation
import Testing
@testable import CandyCorn

@Suite("Session debrief")
struct SessionDebriefViewTests {
    @Test("Therapy projection preserves the five section order and de-duplicates questions")
    func therapyProjection() {
        let duplicate = item(20, "Ask what progress would look like", voice: .patient, timestamp: 20_000)
        let result = summary(
            template: .therapy,
            sections: [
                section(1, .nextSessionItems, [duplicate]),
                section(2, .homework, [item(21, "Write the timeline", voice: .provider)]),
                section(3, .questionsToRevisit, [duplicate, item(22, "What changed?", voice: .candyCorn)]),
                section(4, .goals, [item(23, "Notice guilt", voice: .patient)]),
                section(5, .providerInstructions, [item(24, "TMS only", voice: .provider)]),
                section(6, .unfinishedTopics, [item(25, "The meeting", voice: .patient)]),
            ],
            discussed: [item(26, "Football", voice: .patient)]
        )

        let content = SessionDebriefContent(result: result)

        #expect(SessionDebriefContent.sectionTitles == [
            "What you talked about",
            "What your provider asked you to do",
            "Things that sounded like goals",
            "Talking points you brought that got discussed",
            "Questions left open",
        ])
        #expect(content.topics.count == 3)
        #expect(content.providerRequests.map(\.text) == ["Write the timeline"])
        #expect(content.candidateGoals.map(\.text) == ["Notice guilt"])
        #expect(content.discussedTalkingPoints.map(\.text) == ["Football"])
        #expect(content.openQuestions.map(\.text) == ["Ask what progress would look like", "What changed?", "The meeting"])
        #expect(content.isUsable)
        #expect(SessionDebriefContent(result: summary(template: .therapy, topicCount: 5)).isUsable)
        #expect(!SessionDebriefContent(result: summary(template: .therapy, topicCount: 6)).isUsable)
    }

    @Test("TMS projection uses provider instructions and the TMS open-question kinds")
    func tmsProjection() {
        let result = summary(
            template: .tms,
            sections: [
                section(1, .homework, [item(30, "Therapy only", voice: .provider)]),
                section(2, .providerInstructions, [item(31, "Keep the usual schedule", voice: .provider)]),
                section(3, .questionsForProvider, [item(32, "Is the pressure expected?", voice: .patient)]),
                section(4, .thingsToMonitor, [item(33, "Note how long pressure lasts", voice: .provider)]),
                section(5, .nextSessionItems, [item(34, "Review the pattern", voice: .candyCorn)]),
                section(6, .unfinishedTopics, [item(35, "Therapy question", voice: .patient)]),
            ]
        )

        let content = SessionDebriefContent(result: result)

        #expect(content.providerRequests.map(\.text) == ["Keep the usual schedule"])
        #expect(content.openQuestions.map(\.text) == [
            "Is the pressure expected?", "Note how long pressure lasts", "Review the pattern",
        ])
        #expect(!content.openQuestions.contains { $0.text == "Therapy question" })
    }

    @Test("Empty optional subsections remain empty without fake actions")
    func emptySubsections() {
        let content = SessionDebriefContent(result: summary(template: .therapy))

        #expect(content.isUsable)
        #expect(content.providerRequests.isEmpty)
        #expect(content.candidateGoals.isEmpty)
        #expect(content.discussedTalkingPoints.isEmpty)
        #expect(content.openQuestions.isEmpty)
    }

    @Test("Invalid, missing, corrupt, and wrong-template summaries are unavailable")
    func unavailableFallbacks() throws {
        let appointment = appointment(kind: .therapy)
        let ready = processing(appointmentID: appointment.id, stage: .ready)
        let invalid = StructuredSessionSummaryResult(
            template: .therapy,
            debriefTopics: [item(40, "Only one topic", voice: .patient)],
            sections: [], discussedTalkingPoints: [], metadata: metadata
        )
        let wrongTemplate = summary(template: .tms)
        let corrupt = try? JSONDecoder().decode(
            StructuredSessionSummaryResult.self,
            from: Data("not-json".utf8)
        )

        #expect(SessionDebriefAvailability.resolve(
            appointment: appointment, record: ready, result: nil
        ) == .unavailable)
        #expect(corrupt == nil)
        #expect(SessionDebriefAvailability.resolve(
            appointment: appointment, record: ready, result: corrupt
        ) == .unavailable)
        #expect(SessionDebriefAvailability.resolve(
            appointment: appointment, record: ready, result: invalid
        ) == .unavailable)
        #expect(SessionDebriefAvailability.resolve(
            appointment: appointment, record: ready, result: wrongTemplate
        ) == .unavailable)
        #expect(SessionDebriefAvailability.resolve(
            appointment: appointment,
            record: processing(appointmentID: appointment.id, stage: .separatingSpeakers),
            result: summary(template: .therapy)
        ) == .processing)
    }

    @Test("Homework construction is provider-explicit and keeps the first valid timestamp")
    func homeworkConstruction() throws {
        let appointment = appointment(kind: .therapy)
        let goalID = id(50)
        let decisionID = id(51)
        let source = StructuredSessionSummaryItem(
            id: id(52), text: "  Finish the timeline  ", provenance: .provider,
            evidence: [
                EvidenceCitation(sourceID: id(53), quote: "First", timestampMilliseconds: nil),
                EvidenceCitation(sourceID: id(54), quote: "Second", timestampMilliseconds: 744_000),
            ], relatedEntityID: nil
        )
        let mutation = try #require(SessionDebriefMutationFactory.addHomework(
            item: source, appointment: appointment, goalID: goalID,
            decisionID: decisionID, createdAt: timestamp
        ))
        guard case let .addGoal(decision, goal) = mutation else {
            Issue.record("Expected an add-goal mutation")
            return
        }

        #expect(goal.id == goalID)
        #expect(goal.title == "Finish the timeline")
        #expect(goal.cadence == .homework)
        #expect(goal.source == .providerExplicit)
        #expect(goal.sourceEntityID == appointment.id)
        #expect(goal.sourceTimestampMilliseconds == 744_000)
        #expect(SessionDebriefTimestamp.accessibilityLabel(milliseconds: 744_000)
            == "Play from 12 minutes 24 seconds")
        #expect(goal.status == .active)
        #expect(goal.provenance.voice == .provider)
        #expect(decision.id == decisionID)
        #expect(decision.kind.rawValue == SessionDebriefDecisionKind.addedHomework.rawValue)
        #expect(decision.targetEntityID == goal.id)
        #expect(decision.editedText == nil)
    }

    @Test("Provider requests with patient provenance cannot become homework")
    func rejectsPatientHomework() {
        let mutation = SessionDebriefMutationFactory.addHomework(
            item: item(60, "Try this", voice: .patient), appointment: appointment(kind: .therapy),
            goalID: id(61), decisionID: id(62), createdAt: timestamp
        )
        #expect(mutation == nil)
    }

    @Test("Goal construction preserves voice and saves edited text only on add")
    func goalConstruction() throws {
        let appointment = appointment(kind: .therapy)
        let source = item(70, "Original candidate", voice: .patient, timestamp: 9_200)
        let mutation = try #require(SessionDebriefMutationFactory.addGoal(
            item: source, appointment: appointment, editedText: "  Edited goal  ",
            goalID: id(71), decisionID: id(72), createdAt: timestamp
        ))
        guard case let .addGoal(decision, goal) = mutation else {
            Issue.record("Expected an add-goal mutation")
            return
        }

        #expect(goal.title == "Edited goal")
        #expect(goal.cadence == .oneOff)
        #expect(goal.source == .userExplicit)
        #expect(goal.sourceTimestampMilliseconds == 9_200)
        #expect(goal.provenance.voice == .user)
        #expect(decision.editedText == "Edited goal")
        #expect(decision.kind.rawValue == SessionDebriefDecisionKind.addedGoal.rawValue)
    }

    @Test("Ignore creates only a decision and no goal payload")
    func ignoreWithoutGoal() {
        let appointment = appointment(kind: .therapy)
        let source = item(80, "Candidate", voice: .candyCorn)
        let mutation = SessionDebriefMutationFactory.ignoreGoal(
            item: source, appointmentID: appointment.id,
            decisionID: id(81), createdAt: timestamp
        )
        guard case let .ignoreGoal(decision) = mutation else {
            Issue.record("Expected an ignore mutation")
            return
        }

        #expect(decision.summaryItemID == source.id)
        #expect(decision.kind.rawValue == SessionDebriefDecisionKind.ignoredGoal.rawValue)
        #expect(decision.targetEntityID == nil)
    }

    @Test("Discussed talking point preserves identity and changes only status")
    func discussedTalkingPoint() throws {
        let appointment = appointment(kind: .therapy)
        let point = TalkingPoint(
            id: id(90), text: "Ask about guilt", source: .journal, sourceID: id(91),
            targetAppointmentKind: .therapy, isImportant: true, status: .open,
            createdAt: timestamp,
            provenance: Provenance(
                voice: .user, label: "You saved this", detail: "Journal",
                occurredAt: timestamp, sourceRoute: .bringUp
            )
        )
        let source = StructuredSessionSummaryItem(
            id: id(92), text: point.text, provenance: .patient,
            evidence: [citation(9_000)], relatedEntityID: point.id
        )
        let mutation = try #require(SessionDebriefMutationFactory.markDiscussed(
            item: source, appointmentID: appointment.id, talkingPoints: [point],
            decisionID: id(93), createdAt: timestamp
        ))
        guard case let .markTalkingPointDiscussed(decision, updated) = mutation else {
            Issue.record("Expected a talking-point mutation")
            return
        }
        var expected = point
        expected.status = .discussed

        #expect(updated == expected)
        #expect(decision.targetEntityID == point.id)
        #expect(decision.kind.rawValue == SessionDebriefDecisionKind.markedTalkingPointDiscussed.rawValue)
        #expect(SessionDebriefMutationFactory.markDiscussed(
            item: source, appointmentID: appointment.id, talkingPoints: [],
            decisionID: id(94), createdAt: timestamp
        ) == nil)
    }

    @Test("Pinning creates one open session talking point for the appointment kind")
    func questionPinning() throws {
        let appointment = appointment(kind: .tms)
        let source = item(100, "How long should pressure last?", voice: .provider, timestamp: 21_000)
        let mutation = try #require(SessionDebriefMutationFactory.pinQuestion(
            item: source, appointment: appointment, talkingPointID: id(101),
            decisionID: id(102), createdAt: timestamp
        ))
        guard case let .pinQuestion(decision, point) = mutation else {
            Issue.record("Expected a pin-question mutation")
            return
        }

        #expect(point.id == id(101))
        #expect(point.text == source.text)
        #expect(point.source == .session)
        #expect(point.sourceID == appointment.id)
        #expect(point.targetAppointmentKind == .tms)
        #expect(point.status == .open)
        #expect(point.provenance.voice == .provider)
        #expect(decision.targetEntityID == point.id)
        #expect(decision.kind.rawValue == SessionDebriefDecisionKind.pinnedQuestion.rawValue)
    }

    @Test("Persisted decisions replace their action controls with stable completion text")
    func persistedDecisionPresentation() {
        let appointmentID = id(110)
        let values: [(SessionDebriefDecisionKind, String)] = [
            (.addedHomework, "Added to homework"), (.addedGoal, "Added"),
            (.ignoredGoal, "Ignored"), (.markedTalkingPointDiscussed, "Marked discussed"),
            (.pinnedQuestion, "Pinned"),
        ]
        let decisions = values.enumerated().map { index, value in
            SessionDebriefDecision(
                id: id(120 + index), appointmentID: appointmentID,
                summaryItemID: id(130 + index), kind: value.0,
                targetEntityID: nil, editedText: nil, createdAt: timestamp
            )
        }

        for (index, value) in values.enumerated() {
            #expect(SessionDebriefDecisionPresentation.completion(
                for: id(130 + index), appointmentID: appointmentID, decisions: decisions
            ) == value.1)
        }
        #expect(SessionDebriefDecisionPresentation.completion(
            for: id(999), appointmentID: appointmentID, decisions: decisions
        ) == nil)
    }

    @Test("Projection and Done do not mutate care data")
    @MainActor
    func passivePresentationDoesNotMutate() {
        let state = DemoState(
            dependencies: PreviewDependencies.make(),
            arguments: ["CandyCorn"]
        )
        let navigation = NavigationModel(arguments: ["CandyCorn", "-screen", Route.sessionDebrief.rawValue])
        let counts = (state.goals.count, state.talkingPoints.count, state.debriefDecisions.count)

        _ = SessionDebriefContent(result: summary(template: .therapy))
        _ = SessionDebriefView(navigation: navigation, state: state)
        SessionDebriefNavigation.finish(navigation)

        #expect(navigation.selectedTab == .today)
        #expect(navigation.todayPath.isEmpty)
        #expect(state.goals.count == counts.0)
        #expect(state.talkingPoints.count == counts.1)
        #expect(state.debriefDecisions.count == counts.2)
    }

    @Test("The debrief screen route receives deterministic ready content")
    @MainActor
    func deterministicScreenshotSeed() throws {
        let state = DemoState(arguments: ["CandyCorn", "-screen", Route.sessionDebrief.rawValue])
        let record = try #require(state.sessionProcessingRecord(for: SeededData.therapySessionID))
        let result = try #require(state.structuredSessionSummary(for: SeededData.therapySessionID)?.result)

        #expect(record.stage == .ready)
        #expect(record.progress == 1)
        #expect(result.template == .therapy)
        #expect(SessionDebriefContent(result: result).isUsable)
    }

    private let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
    private let metadata = AIResultMetadata(
        provider: "test", model: "test-model",
        usage: AIUsage(
            promptTokens: nil, completionTokens: nil, reasoningTokens: nil,
            totalTokens: nil, costCredits: nil
        )
    )

    private func summary(
        template: SessionSummaryTemplate,
        topicCount: Int = 3,
        sections: [StructuredSessionSummarySection] = [],
        discussed: [StructuredSessionSummaryItem] = []
    ) -> StructuredSessionSummaryResult {
        StructuredSessionSummaryResult(
            template: template,
            debriefTopics: (0..<topicCount).map {
                item($0 + 1, "Topic \($0 + 1)", voice: $0 % 2 == 0 ? .patient : .provider)
            },
            sections: sections, discussedTalkingPoints: discussed, metadata: metadata
        )
    }

    private func section(
        _ value: Int,
        _ kind: SessionSummarySectionKind,
        _ items: [StructuredSessionSummaryItem]
    ) -> StructuredSessionSummarySection {
        StructuredSessionSummarySection(
            id: id(500 + value), kind: kind, title: kind.rawValue, items: items
        )
    }

    private func item(
        _ value: Int,
        _ text: String,
        voice: SessionSummaryItemProvenance,
        timestamp: Int = 1_000
    ) -> StructuredSessionSummaryItem {
        StructuredSessionSummaryItem(
            id: id(value), text: text, provenance: voice,
            evidence: [citation(timestamp)], relatedEntityID: nil
        )
    }

    private func citation(_ timestamp: Int) -> EvidenceCitation {
        EvidenceCitation(sourceID: id(800 + timestamp), quote: "Evidence", timestampMilliseconds: timestamp)
    }

    private func appointment(kind: Appointment.Kind) -> Appointment {
        Appointment(
            id: id(kind == .tms ? 901 : 900), kind: kind,
            scheduledAt: timestamp, startedAt: timestamp,
            endedAt: timestamp.addingTimeInterval(3_600), providerID: nil,
            providerName: "Dr. Morgan", recordingAttachmentID: id(902),
            transcriptID: id(903), summaryID: id(904), status: .completed
        )
    }

    private func processing(
        appointmentID: UUID,
        stage: SessionProcessingStage
    ) -> SessionProcessingRecord {
        SessionProcessingRecord(
            id: id(910), appointmentID: appointmentID, stage: stage,
            progress: stage == .ready ? 1 : 0.5, summaryConsentGranted: true,
            failure: nil, updatedAt: timestamp
        )
    }

    private func id(_ value: Int) -> UUID {
        let suffix = String(format: "%012d", value)
        return UUID(uuidString: "A0000000-0000-4000-8000-\(suffix)")!
    }
}
