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
        V2Screen(
            title: "Recording is not active",
            subtitle: "Confirm permission before a recording can start.",
            backAction: navigation.backAction(for: .activeAppointment),
            backLabel: "Close",
            backIcon: .close
        ) {
            StatusNotice(title: "Permission has not been confirmed", detail: "No microphone request was made and no recording started.", kind: .warning)
            V2GroupCard {
                V2ListRow(icon: .shield, title: "Review recording permission", detail: "Choose the visit type and confirm consent.", divider: false) {
                    navigation.goBack(from: .activeAppointment)
                    navigation.navigate(to: .recordAppointment)
                }
            }
        }
    }

    private var activeRecorder: some View {
        VStack(spacing: DesignTokens.Spacing.large) {
            HStack {
                RoundActionButton(icon: .back, label: "Leave recording screen", action: close)
                Spacer()
                Text(state.selectedAppointmentKind.displayName)
                    .font(TypeScale.metaStrong)
                    .foregroundStyle(DesignTokens.cocoaSoft)
            }
            Spacer(minLength: DesignTokens.Spacing.large)
            HStack(spacing: 6) {
                Circle().fill(DesignTokens.rose).frame(width: 8, height: 8)
                Text("Recording").font(TypeScale.metaStrong).foregroundStyle(DesignTokens.cocoaSoft)
            }
            Text(VoiceJournalView.format(milliseconds: state.recordingSnapshot.elapsedMilliseconds))
                .font(TypeScale.timer).monospacedDigit()
                .accessibilityLabel("Appointment recording duration")
            AppointmentWaveform(level: state.dependencies.screenshotMode ? 1 : state.recordingSnapshot.normalizedLevel)
                .frame(height: 112)
                .padding(.vertical, DesignTokens.Spacing.xLarge)
            Button(isStopping ? "Saving" : "Stop", action: finish)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isStopping)
                .frame(maxWidth: 160)
            Spacer(minLength: DesignTokens.Spacing.large)
            Text("Recording continues if you leave this screen or lock the phone.")
                .font(TypeScale.meta).foregroundStyle(DesignTokens.cocoaSoft)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(DesignTokens.cocoa)
        .padding(.horizontal, DesignTokens.screenInset)
        .padding(.top, DesignTokens.Spacing.small)
        .padding(.bottom, DesignTokens.Spacing.section)
    }

    private var savedRecording: some View {
        V2Screen(
            title: state.latestRecording?.stopReason == .interruption ? "Recording stopped" : "Saved on this device",
            subtitle: "The original recording is preserved locally.",
            backAction: navigation.backAction(for: .activeAppointment),
            backLabel: "Close",
            backIcon: .close
        ) {
            StatusNotice(
                title: "Saved on this device",
                detail: "On-device transcription starts after the saved recording is linked to this appointment.",
                kind: .saved
            )
            if let attachment = state.latestRecording?.attachment {
                V2GroupCard {
                    V2ListRow(icon: .play, title: "Play recording", detail: "Listen to the saved original.", divider: false) {
                        Task { try? await state.dependencies.playback.play(attachment: attachment) }
                    }
                }
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
