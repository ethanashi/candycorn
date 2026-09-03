import Foundation
import Testing
@testable import CandyCorn

@Suite("Organizer care surfaces")
@MainActor
struct OrganizerCareFeatureTests {
    @Test("Session disclosure contains manual notes only")
    func sessionDisclosureUsesOnlyManualNotes() throws {
        let state = DemoState(arguments: ["CandyCorn"])
        let appointment = try #require(state.appointments.first { !$0.manualNotes.isEmpty })
        let transcriptBefore = state.transcript
        let recordingBefore = appointment.recordingAttachmentID

        let pending = try state.prepareAISend(.summarizeSession(appointment.id))

        #expect(pending.disclosure.sources.count == 1)
        #expect(pending.disclosure.sources[0].id == appointment.id)
        #expect(pending.disclosure.sources[0].characterCount == appointment.manualNotes.count)
        #expect(pending.disclosure.totalImageCount == 0)
        #expect(state.transcript == transcriptBefore)
        #expect(state.appointments.first { $0.id == appointment.id }?.recordingAttachmentID == recordingBefore)
    }

    @Test("Blank manual notes cannot prepare a summary")
    func blankNotesCannotPrepare() async throws {
        let state = DemoState(arguments: ["CandyCorn"])
        var appointment = try #require(state.appointments.first { $0.kind == .therapy && $0.status == .completed })
        appointment.manualNotes = " \n "
        #expect(await state.saveAppointment(appointment))
        #expect(throws: UserFacingError.aiSource) {
            _ = try state.prepareAISend(.summarizeSession(appointment.id))
        }
    }

    @Test("Generated brief edits preserve artifact identity and source records")
    func generatedEditPreservesSources() async throws {
        let state = DemoState(arguments: ["CandyCorn"])
        let artifact = try #require(state.artifacts.first { $0.kind == .appointmentBrief })
        let journalsBefore = state.journals
        let appointmentsBefore = state.appointments
        var editor = try #require(AppointmentBriefEditor(artifact: artifact))
        let firstSection = try #require(editor.saved.sections.first)
        let firstStatement = try #require(firstSection.statements.first)

        editor.begin()
        editor.update(sectionID: firstSection.id, statementID: firstStatement.id, text: "I want to revisit the football story and the guilt that followed relief.")
        let prepared = editor.preparedSave(at: Date(timeIntervalSince1970: 1_788_700_000))
        let edited = try #require(prepared)
        #expect(await state.saveEditedAppointmentBrief(artifact.id, result: edited))

        let replacement = try #require(state.artifacts.first { $0.id == artifact.id })
        let result = try JSONDecoder().decode(AppointmentBriefResult.self, from: replacement.structuredPayload)
        #expect(replacement.provider == artifact.provider)
        #expect(replacement.model == artifact.model)
        #expect(replacement.sourceIDs == artifact.sourceIDs)
        #expect(replacement.createdAt == artifact.createdAt)
        #expect(result.userEditedAt != nil)
        #expect(state.journals == journalsBefore)
        #expect(state.appointments == appointmentsBefore)
    }

    @Test("Generated brief cancellation restores every statement")
    func generatedEditCancellation() throws {
        let artifact = try #require(SeededData.aiArtifacts.first { $0.kind == .appointmentBrief })
        var editor = try #require(AppointmentBriefEditor(artifact: artifact))
        let saved = editor.saved
        let section = try #require(saved.sections.first)
        let statement = try #require(section.statements.first)

        editor.begin()
        editor.update(sectionID: section.id, statementID: statement.id, text: "Temporary wording")
        editor.cancel()

        #expect(editor.saved == saved)
        #expect(editor.draft == saved)
        #expect(!editor.isEditing)
    }

    @Test("TMS generated output rejects causality and treatment changes")
    func tmsSafety() {
        #expect(AppointmentBriefSafety.isSafeForTMS(result(text: "Mood was quieter after the saved visit.")))
        #expect(!AppointmentBriefSafety.isSafeForTMS(result(text: "TMS caused the mood improvement.")))
        #expect(!AppointmentBriefSafety.isSafeForTMS(result(text: "TMS led to a quieter mood.")))
        #expect(!AppointmentBriefSafety.isSafeForTMS(result(text: "Change your treatment before the next visit.")))
        #expect(!AppointmentBriefSafety.isSafeForTMS(result(text: "Increase stimulation at the next appointment.")))
    }

    @Test("Appointment artifacts stay with their appointment kind")
    func artifactKindRouting() {
        let therapyID = UUID()
        let tmsID = UUID()
        let therapy = appointment(id: therapyID, kind: .therapy)
        let tms = appointment(id: tmsID, kind: .tms)
        let therapyArtifact = artifact(sourceID: therapyID, text: "Bring the football question to therapy.", seconds: 1)
        let tmsArtifact = artifact(sourceID: tmsID, text: "Track the saved headache observation.", seconds: 2)
        let artifacts = [therapyArtifact, tmsArtifact]

        let selectedTherapy = AppointmentBriefArtifactReader.latest(
            kind: .therapy, preferredID: nil, artifacts: artifacts,
            appointments: [therapy, tms], goals: [], talkingPoints: []
        )
        let selectedTMS = AppointmentBriefArtifactReader.latest(
            kind: .tms, preferredID: nil, artifacts: artifacts,
            appointments: [therapy, tms], goals: [], talkingPoints: []
        )

        #expect(selectedTherapy?.id == therapyArtifact.id)
        #expect(selectedTMS?.id == tmsArtifact.id)
    }

    @Test("AI off leaves both manual brief editors usable")
    func manualFallbacksRemainUsable() {
        let state = DemoState(arguments: ["CandyCorn"])
        var therapy = TherapyBriefEditor()
        var tms = TMSBriefEditor()
        #expect(state.aiMode == .off)

        therapy.begin()
        therapy.update(.possibleOpening, text: "I want to talk about football and guilt.")
        tms.begin()
        tms.update(.question, text: "Should I keep tracking this mild headache?")

        let therapySaved = therapy.save()
        let tmsSaved = tms.save()
        #expect(therapySaved)
        #expect(tmsSaved)
    }

    private func result(text: String, sourceID: UUID = UUID()) -> AppointmentBriefResult {
        AppointmentBriefResult(
            sections: [AppointmentBriefSection(
                id: UUID(),
                title: "What matters",
                statements: [EvidenceBackedStatement(
                    id: UUID(), text: text,
                    evidence: [EvidenceCitation(sourceID: sourceID, quote: "Saved evidence", timestampMilliseconds: nil)]
                )]
            )],
            userEditedAt: nil,
            metadata: metadata
        )
    }

    private func artifact(sourceID: UUID, text: String, seconds: TimeInterval) -> AIArtifact {
        let payload = try? JSONEncoder().encode(result(text: text, sourceID: sourceID))
        return AIArtifact(
            id: UUID(), kind: .appointmentBrief, sourceIDs: [sourceID],
            provider: "fixture-router", model: "fixture-model",
            structuredPayload: payload ?? Data(), createdAt: Date(timeIntervalSince1970: seconds)
        )
    }

    private func appointment(id: UUID, kind: Appointment.Kind) -> Appointment {
        Appointment(
            id: id, kind: kind, scheduledAt: Date(timeIntervalSince1970: 1), startedAt: nil,
            endedAt: nil, providerID: nil, providerName: "Fictional provider",
            recordingAttachmentID: nil, transcriptID: nil, summaryID: nil, status: .completed
        )
    }

    private var metadata: AIResultMetadata {
        AIResultMetadata(
            provider: "fixture-router", model: "fixture-model",
            usage: AIUsage(promptTokens: nil, completionTokens: nil, reasoningTokens: nil, totalTokens: nil, costCredits: nil)
        )
    }
}
