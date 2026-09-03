import SwiftUI

struct TMSPostSessionView: View {
    @Bindable var navigation: NavigationModel
    @Bindable var state: DemoState
    @State private var snapshot = TMSCheckInSnapshot(mood: 6, anxiety: 5, energy: 4, distress: 5)
    @State private var providerInstructions = "Keep the usual schedule and note anything you want to discuss next time."
    @State private var nextItem = "Ask whether the head pressure is expected to stay this brief."
    @State private var saved = false
    @State private var isSaving = false
    @State private var pendingSend: PendingAISend?
    @State private var sendTask: Task<Void, Never>?
    @State private var relabelingSegmentIDs: Set<UUID> = []
    @State private var processingError: String?

    var body: some View {
        Group {
            if saved { savedView } else { checkInView }
        }
        .sheet(item: $pendingSend, onDismiss: cancelSend) { pending in
            WhatLeavesDeviceSheet(
                pending: pending,
                processingState: state.aiProcessingState(for: pending.action),
                onSend: { send(pending) },
                onCancel: cancelSend
            )
        }
        .onDisappear(perform: cancelSend)
    }

    private var checkInView: some View {
        ScreenLayout(
            title: "After TMS",
            subtitle: "Record what you notice without assigning a cause.",
            backAction: navigation.backAction(for: .tmsPost),
            bottomInset: DesignTokens.Spacing.section
        ) {
            TMSMeasuresEditor(snapshot: $snapshot)
            noteField(title: "Provider instruction notes", text: $providerInstructions)
            ProvenanceLine(provenance: providerProvenance)
            noteField(title: "One thing for next session", text: $nextItem)
            Text("This check-in records timing and context. It does not claim that TMS caused a mood or symptom change.")
                .font(TypeScale.label)
                .tracking(0)
                .foregroundStyle(DesignTokens.cocoaSoft)
                .fixedSize(horizontal: false, vertical: true)
                .padding(DesignTokens.Spacing.base)
                .background(DesignTokens.surfaceWarm)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.controlRadius))
            Button(isSaving ? "Saving" : "Save post-session check-in") {
                saveCheckIn()
            }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isSaving)
            if let appointment = sessionAppointment {
                Text("Saved appointment audio")
                    .font(TypeScale.sectionCompact)
                    .tracking(-0.1)
                    .foregroundStyle(DesignTokens.cocoa)
                SessionProcessingStatusView(
                    record: state.sessionProcessingRecord(for: appointment.id),
                    onReviewSummary: prepareProcessedSummary,
                    onRetry: retryProcessing,
                    onOpenDebrief: openDebrief
                )
                SessionTranscriptView(
                    segments: state.transcript.filter { $0.appointmentID == appointment.id },
                    providerName: appointment.providerName,
                    providerRole: "Provider",
                    sessionDate: (appointment.startedAt ?? appointment.scheduledAt)?
                        .formatted(.dateTime.month(.abbreviated).day()),
                    isRelabeling: { relabelingSegmentIDs.contains($0.id) },
                    onLabel: persistLabel,
                    onTimestamp: { segment in
                        Task {
                            _ = await state.playSessionRecording(
                                appointmentID: appointment.id,
                                fromMilliseconds: segment.startMilliseconds
                            )
                        }
                    }
                )
                if let processingError {
                    StatusNotice(title: "Processing paused", detail: processingError, kind: .warning)
                }
            }
        }
    }

    private var savedView: some View {
        ScreenLayout(
            title: "Post-session check-in saved",
            subtitle: "Saved on this device.",
            backAction: navigation.backAction(for: .tmsPost),
            bottomInset: DesignTokens.Spacing.section
        ) {
            StatusNotice(
                title: "Saved on this device",
                detail: "Your notes are recorded without claiming what caused a change.",
                kind: .saved
            )
            Button("Open History") { navigation.navigate(to: .history) }
                .buttonStyle(PrimaryButtonStyle())
            Button("Prepare for TMS") { navigation.navigate(to: .prepareTMS) }
                .buttonStyle(SecondaryButtonStyle())
        }
    }

    private var providerProvenance: Provenance {
        Provenance(
            voice: .provider,
            label: "TMS team said this",
            detail: "Post-session instructions, Sep 5 at 9:56 AM",
            occurredAt: nil,
            sourceRoute: .tmsPost
        )
    }

    private var sessionAppointment: Appointment? {
        if let id = state.selectedAppointmentID,
           let selected = state.appointments.first(where: {
               $0.id == id && $0.kind == .tms && $0.recordingAttachmentID != nil
           }) { return selected }
        return state.appointments.filter {
            $0.kind == .tms && $0.recordingAttachmentID != nil
        }.max { ($0.startedAt ?? .distantPast) < ($1.startedAt ?? .distantPast) }
    }

    private func noteField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text(title).font(TypeScale.sectionCompact).tracking(-0.1)
            TextEditor(text: text)
                .font(TypeScale.body)
                .scrollContentBackground(.hidden)
                .padding(DesignTokens.Spacing.compact)
                .frame(minHeight: 104)
                .background(DesignTokens.surface)
                .overlay(RoundedRectangle(cornerRadius: DesignTokens.controlRadius).stroke(DesignTokens.hairline))
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.controlRadius))
                .accessibilityLabel(title)
        }
        .foregroundStyle(DesignTokens.cocoa)
    }

    private func saveCheckIn() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            let mood = MoodLog(
                id: UUID(), createdAt: state.dependencies.now(), mood: snapshot.mood,
                anxiety: snapshot.anxiety, energy: snapshot.energy,
                customValues: ["distress": snapshot.distress], note: nil
            )
            guard await state.persistMood(mood) else {
                isSaving = false
                return
            }
            if !nextItem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                _ = await state.createTalkingPoint(text: nextItem, source: .manual, targetAppointmentKind: .tms)
            }
            saved = true
            isSaving = false
        }
    }

    private func prepareProcessedSummary() {
        guard pendingSend == nil, let id = sessionAppointment?.id else { return }
        do {
            pendingSend = try state.prepareProcessedSessionSummary(appointmentID: id)
            processingError = nil
        } catch let error as UserFacingError {
            processingError = error.message
        } catch {
            processingError = "This transcript is not ready to send."
        }
    }

    private func send(_ pending: PendingAISend) {
        guard sendTask == nil else { return }
        if case .failed = state.aiProcessingState(for: pending.action) {
            pendingSend = nil
            prepareProcessedSummary()
            return
        }
        sendTask = Task {
            let succeeded = await state.performAISend(pending)
            sendTask = nil
            if succeeded {
                pendingSend = nil
            } else if case let .failed(message) = state.aiProcessingState(for: pending.action) {
                processingError = message
            }
        }
    }

    private func cancelSend() {
        sendTask?.cancel()
        sendTask = nil
        pendingSend = nil
    }

    private func retryProcessing() {
        guard let id = sessionAppointment?.id else { return }
        Task { await state.retrySessionProcessing(appointmentID: id) }
    }

    private func persistLabel(_ segment: TranscriptSegment, _ speaker: TranscriptSegment.Speaker) {
        guard !relabelingSegmentIDs.contains(segment.id) else { return }
        relabelingSegmentIDs.insert(segment.id)
        Task {
            _ = await state.persistSpeakerCluster(segmentID: segment.id, as: speaker)
            relabelingSegmentIDs.remove(segment.id)
        }
    }

    private func openDebrief() {
        guard let route = Route(rawValue: "/sessions/therapy-sep-2/debrief") else { return }
        navigation.navigate(to: route)
    }
}
