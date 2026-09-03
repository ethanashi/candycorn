import SwiftUI

struct ActiveAppointmentView: View {
    @Bindable var navigation: NavigationModel
    @Bindable var state: DemoState
    @State private var isStopping = false

    var body: some View {
        Group {
            if state.activeRecordingKind != nil || state.recordingSnapshot.isRecording {
                activeRecorder
            } else if state.latestRecording != nil {
                savedRecording
            } else {
                permissionGuard
            }
        }
        .background(DesignTokens.canvas.ignoresSafeArea())
        .task { await prepareScreenshotRecordingIfNeeded() }
    }

    private var permissionGuard: some View {
        ScreenLayout(title: "Recording is not active", subtitle: "Confirm permission before a recording can start.", backAction: navigation.backAction(for: .activeAppointment)) {
            StatusNotice(title: "Permission has not been confirmed", detail: "No microphone request was made and no recording started.", kind: .warning)
            Button("Review recording permission") {
                navigation.goBack(from: .activeAppointment)
                navigation.navigate(to: .recordAppointment)
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    private var activeRecorder: some View {
        VStack(spacing: DesignTokens.Spacing.large) {
            HStack {
                Button(action: close) {
                    Image(systemName: AppIcon.back.rawValue)
                        .frame(width: DesignTokens.controlMinimum, height: DesignTokens.controlMinimum)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Leave recording screen")
                Spacer()
                Text(state.selectedAppointmentKind.displayName).font(TypeScale.bodyMedium)
            }
            Spacer(minLength: DesignTokens.Spacing.large)
            Text("Recording").font(TypeScale.bodyMedium)
            Text(VoiceJournalView.format(milliseconds: state.recordingSnapshot.elapsedMilliseconds))
                .font(TypeScale.timer).monospacedDigit()
                .accessibilityLabel("Appointment recording duration")
            AppointmentWaveform(level: state.recordingSnapshot.normalizedLevel)
                .padding(.vertical, DesignTokens.Spacing.section)
            Button(isStopping ? "Saving" : "Finish", action: finish)
                .buttonStyle(DangerButtonStyle())
                .disabled(isStopping)
                .frame(maxWidth: 180)
            Spacer(minLength: DesignTokens.Spacing.large)
            Text("Recording continues if you leave this screen or lock the phone.")
                .font(TypeScale.provenance).foregroundStyle(DesignTokens.cocoaSoft)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(DesignTokens.cocoa)
        .padding(.horizontal, DesignTokens.screenInset)
        .padding(.bottom, DesignTokens.Spacing.section)
    }

    private var savedRecording: some View {
        ScreenLayout(
            title: state.latestRecording?.stopReason == .interruption ? "Recording stopped" : "Saved on this device",
            subtitle: "The original recording is preserved locally.",
            backAction: navigation.backAction(for: .activeAppointment)
        ) {
            StatusNotice(
                title: "Saved on this device",
                detail: "On-device transcription starts after the saved recording is linked to this appointment.",
                kind: .saved
            )
            if let attachment = state.latestRecording?.attachment {
                Button {
                    Task { try? await state.dependencies.playback.play(attachment: attachment) }
                } label: {
                    Label("Play recording", systemImage: AppIcon.play.rawValue)
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            Button(savedActionTitle, action: openSavedDestination).buttonStyle(PrimaryButtonStyle())
        }
    }

    private var savedActionTitle: String {
        state.selectedAppointmentKind == .therapy ? "Open session detail" : "Back to appointments"
    }

    private func finish() {
        guard !isStopping else { return }
        isStopping = true
        Task {
            _ = await state.stopRecording(reason: .user)
            if let duration = state.latestRecording?.attachment.durationMilliseconds {
                _ = state.finishAppointmentRecording(durationSeconds: duration / 1_000)
            }
            isStopping = false
        }
    }

    private func close() {
        navigation.goBack(from: .activeAppointment)
        navigation.navigate(to: .appointments)
    }

    private func openSavedDestination() {
        navigation.goBack(from: .activeAppointment)
        navigation.navigate(to: state.selectedAppointmentKind == .therapy ? .therapySession : .appointments)
    }

    private func prepareScreenshotRecordingIfNeeded() async {
        guard state.dependencies.screenshotMode,
              state.activeRecordingKind == nil,
              case .recording = state.appointmentRecording else { return }
        let id = state.appointments.first?.id ?? UUID()
        _ = await state.startRecording(kind: .appointment(id: id))
    }
}
