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
        VStack(spacing: 0) {
            HStack {
                Button(action: close) {
                    Image(systemName: AppIcon.close.rawValue)
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: DesignTokens.controlMinimum, height: DesignTokens.controlMinimum)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Leave recording screen")
                Spacer()
                Button("Cancel", action: close)
                    .font(TypeScale.label)
                    .fontWeight(.semibold)
                    .tracking(0)
                    .frame(minHeight: DesignTokens.controlMinimum)
                    .buttonStyle(.plain)
            }
            VStack(spacing: DesignTokens.Spacing.xSmall) {
                Text("\(state.selectedAppointmentKind.displayName) appointment")
                    .font(TypeScale.section)
                    .tracking(-0.2)
                Text("Recording stays on this device")
                    .font(TypeScale.label)
                    .tracking(0)
                    .foregroundStyle(DesignTokens.cocoaSoft)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)

            Spacer(minLength: DesignTokens.Spacing.xLarge)

            VStack(spacing: 0) {
                Text(state.dependencies.screenshotMode ? "Simulated recording" : "Recording")
                    .font(TypeScale.label)
                    .fontWeight(.semibold)
                    .tracking(0)
                    .padding(.bottom, 18)
                Text(VoiceJournalView.format(milliseconds: state.recordingSnapshot.elapsedMilliseconds))
                    .font(Font.custom("AvenirNext-DemiBold", size: 54, relativeTo: .largeTitle))
                    .tracking(-2)
                    .monospacedDigit()
                    .accessibilityLabel("Appointment recording duration")
                    .padding(.bottom, 28)
                AppointmentWaveform(
                    level: state.dependencies.screenshotMode ? 1 : state.recordingSnapshot.normalizedLevel
                )
                .frame(height: 112)
                .padding(.bottom, 36)
                Button(isStopping ? "Saving" : "Stop", action: finish)
                    .font(TypeScale.button)
                    .tracking(0)
                    .foregroundStyle(Color.white)
                    .frame(width: 112)
                    .frame(minHeight: DesignTokens.primaryButtonHeight)
                    .background(DesignTokens.orange)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.controlRadius, style: .continuous))
                    .buttonStyle(.plain)
                    .disabled(isStopping)
                Text("Recording continues if you leave this screen or lock the phone. The original audio is saved before any organization begins.")
                    .font(TypeScale.provenance)
                    .tracking(0)
                    .foregroundStyle(DesignTokens.cocoaSoft)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 290)
                    .padding(.top, DesignTokens.Spacing.large)
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: DesignTokens.Spacing.large)
        }
        .foregroundStyle(DesignTokens.cocoa)
        .padding(.horizontal, DesignTokens.screenInset)
        .padding(.bottom, DesignTokens.Spacing.large)
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
