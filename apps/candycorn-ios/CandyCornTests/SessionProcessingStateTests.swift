import Foundation
import Testing
@testable import CandyCorn

@Suite("Session processing state")
@MainActor
struct SessionProcessingStateTests {
    @Test("Processed disclosure includes transcript text and no audio or images")
    func disclosure() throws {
        let state = DemoState(arguments: ["CandyCorn", "-screen", "/sessions/therapy-sep-2"])
        let pending = try state.prepareProcessedSessionSummary(appointmentID: SeededData.therapySessionID)
        #expect(pending.action == .summarizeProcessedSession(SeededData.therapySessionID))
        #expect(pending.disclosure.purpose == "Create this session debrief")
        #expect(pending.disclosure.destination == "OpenRouter")
        #expect(pending.disclosure.totalImageCount == 0)
        #expect(pending.disclosure.sources.allSatisfy { $0.kind == .text && $0.imageCount == 0 })
        #expect(pending.disclosure.totalCharacterCount == pending.disclosure.sources.reduce(0) { $0 + $1.characterCount })
    }

    @Test("Screenshot seed supplies ready structured therapy data")
    func screenshotSeed() {
        let state = DemoState(arguments: ["CandyCorn", "-screen", "/sessions/therapy-sep-2/debrief"])
        #expect(state.sessionProcessingRecord(for: SeededData.therapySessionID)?.stage == .ready)
        #expect(state.structuredSessionSummary(for: SeededData.therapySessionID)?.result.template == .therapy)
        #expect(state.structuredSessionSummary(for: SeededData.therapySessionID)?.result.debriefTopics.count == 3)
    }

    @Test("Saving an appointment recording starts processing after both records exist")
    func automaticStart() async throws {
        let appointment = Appointment(
            id: UUID(), kind: .therapy, scheduledAt: Date(timeIntervalSince1970: 10),
            startedAt: nil, endedAt: nil, providerID: nil, providerName: "Dr. Morgan",
            recordingAttachmentID: nil, transcriptID: nil, summaryID: nil, status: .planned
        )
        var snapshot = SeededData.emptySnapshot
        snapshot.appointments = [appointment]
        let store = InMemoryCareStore(snapshot: snapshot)
        let processing = FakeSessionProcessing()
        let dependencies = makeDependencies(store: store, processing: processing)
        let state = DemoState(dependencies: dependencies)
        await state.load()

        let started = await state.startRecording(kind: .appointment(id: appointment.id))
        #expect(started)
        _ = await state.stopRecording()

        #expect(await processing.beginCallCount == 1)
        let saved = try #require(state.appointments.first)
        #expect(saved.recordingAttachmentID != nil)
        #expect(saved.status == .processing)
        #expect(state.attachments.contains { $0.id == saved.recordingAttachmentID })
    }

    @Test("Cluster correction survives a fresh DemoState and relabels every matching row")
    func persistentClusterCorrection() async throws {
        let (root, database, store, _, _) = try VaultTestSupport.make(name: "state-cluster-\(UUID().uuidString)")
        defer { VaultTestSupport.remove(root) }
        try await store.setSampleContentEnabled(false)
        let appointment = Appointment(
            id: UUID(), kind: .therapy, scheduledAt: nil, startedAt: Date(timeIntervalSince1970: 1),
            endedAt: Date(timeIntervalSince1970: 2), providerID: nil, providerName: "Dr. Morgan",
            recordingAttachmentID: nil, transcriptID: nil, summaryID: nil, status: .processing
        )
        try await store.saveAppointment(appointment)
        let segments = [
            TranscriptSegment(id: UUID(), appointmentID: appointment.id, speaker: .unknown, rawSpeakerLabel: "speaker-a", startMilliseconds: 0, endMilliseconds: 500, text: "First line", confidence: 0.9),
            TranscriptSegment(id: UUID(), appointmentID: appointment.id, speaker: .unknown, rawSpeakerLabel: "speaker-a", startMilliseconds: 600, endMilliseconds: 1_000, text: "Second line", confidence: 0.9),
        ]
        try await store.replaceTranscriptSegments(segments, for: appointment.id)
        let dependencies = makeDependencies(store: store, maintenance: database, processing: FakeSessionProcessing())
        let state = DemoState(dependencies: dependencies)
        await state.load()

        let persisted = await state.persistSpeakerCluster(segmentID: segments[0].id, as: .patient)
        #expect(persisted)
        let fresh = DemoState(dependencies: dependencies)
        await fresh.load()
        #expect(fresh.transcript.count == 2)
        #expect(fresh.transcript.allSatisfy { $0.speaker == .patient && $0.rawSpeakerLabel == "speaker-a" })
        #expect(fresh.speakerAssignments.count == 1)
    }

    private func makeDependencies(
        store: any CareStore,
        maintenance: (any VaultMaintenance)? = nil,
        processing: any SessionProcessing
    ) -> AppDependencies {
        let attachments = InMemoryAttachmentStore()
        let resolvedMaintenance: any VaultMaintenance
        if let maintenance {
            resolvedMaintenance = maintenance
        } else {
            resolvedMaintenance = InMemoryCareStore(snapshot: SeededData.emptySnapshot)
        }
        return AppDependencies(
            careStore: store,
            maintenance: resolvedMaintenance,
            attachments: attachments,
            recording: FakeRecordingService(attachments: attachments),
            playback: FakeAudioPlaybackService(),
            photos: FakePhotoAttachmentService(),
            exporter: FakeVaultExporter(store: store, attachments: attachments),
            logger: NoOpEventLogger(),
            sessionProcessing: processing,
            screenshotMode: false,
            now: { Date(timeIntervalSince1970: 100) }
        )
    }
}
