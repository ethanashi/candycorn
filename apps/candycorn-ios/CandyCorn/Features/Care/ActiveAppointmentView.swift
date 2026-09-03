import SwiftUI

struct ActiveAppointmentView: View {
    @Bindable var navigation: NavigationModel
    @Bindable var state: DemoState
    @State private var clock = AppointmentRecordingClock()

    var body: some View {
        Group {
            switch state.appointmentRecording {
            case .idle:
                permissionGuard
            case .recording where state.consentAcknowledged:
                activeRecorder
            case .saved:
                savedRecording
            case .recording:
                permissionGuard
            }
        }
        .background(DesignTokens.canvas.ignoresSafeArea())
        .task(id: clock.isRunning && hasActiveRecording) {
            guard clock.isRunning, hasActiveRecording else { return }
            for _ in 0..<86_400 {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
                guard clock.isRunning, hasActiveRecording, !Task.isCancelled else { return }
                clock.tick()
            }
        }
        .onDisappear { clock.cancel() }
    }

    private var permissionGuard: some View {
        ScreenLayout(
            title: "Recording is not active",
            subtitle: "Confirm permission before a recording can start.",
            backAction: close,
            backLabel: "Back to appointments",
            bottomInset: DesignTokens.Spacing.section
        ) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                StatusNotice(
                    title: "Permission has not been confirmed",
                    detail: "No microphone request was made and no recording started.",
                    kind: .warning
                )
                Button("Review recording permission") {
                    clearMalformedRecording()
                    navigation.navigate(to: .recordAppointment)
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .padding(DesignTokens.Spacing.base)
            .background(DesignTokens.surfaceWarm)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous))
        }
    }

    private var activeRecorder: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: close) {
                    Image(systemName: AppIcon.back.rawValue)
                        .frame(width: DesignTokens.controlMinimum, height: DesignTokens.controlMinimum)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to appointments")
                Spacer()
                Text(state.selectedAppointmentKind.displayName)
                    .font(TypeScale.bodyMedium)
            }

            Spacer(minLength: DesignTokens.Spacing.generous)
            Text("Simulated recording")
                .font(TypeScale.bodyMedium)
            Text(AppointmentRecordingClock.format(seconds: clock.elapsedSeconds))
                .font(TypeScale.timer)
                .monospacedDigit()
                .padding(.top, DesignTokens.Spacing.compact)
                .accessibilityLabel("Appointment recording duration")
                .accessibilityValue(AppointmentRecordingClock.format(seconds: clock.elapsedSeconds))

            AppointmentWaveform(phase: clock.elapsedSeconds)
                .padding(.vertical, DesignTokens.Spacing.section)

            Button(action: finish) {
                Label("Finish", systemImage: AppIcon.stop.rawValue)
                    .frame(minWidth: 126)
            }
            .buttonStyle(DangerButtonStyle())
            .frame(maxWidth: 180)

            Spacer(minLength: DesignTokens.Spacing.generous)
            Text("This is a simulated recording. No microphone or background recording is active.")
                .font(TypeScale.provenance)
                .foregroundStyle(DesignTokens.cocoaSoft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 320)
        }
        .foregroundStyle(DesignTokens.cocoa)
        .padding(.horizontal, DesignTokens.screenInset)
        .padding(.top, DesignTokens.Spacing.xSmall)
        .padding(.bottom, DesignTokens.Spacing.section)
    }

    private var savedRecording: some View {
        ScreenLayout(
            title: "Saved on this device",
            subtitle: "The simulated recording is preserved locally. Nothing was sent anywhere.",
            backAction: close,
            backLabel: "Back to appointments",
            bottomInset: DesignTokens.Spacing.section
        ) {
            StatusNotice(
                title: "Saved on this device",
                detail: "No audio was recorded. This recording was simulated.",
                kind: .saved
            )
            Button(savedActionTitle, action: openSavedDestination)
                .buttonStyle(PrimaryButtonStyle())
        }
    }

    private var hasActiveRecording: Bool {
        guard state.consentAcknowledged else { return false }
        if case .recording = state.appointmentRecording { return true }
        return false
    }

    private var savedActionTitle: String {
        switch state.selectedAppointmentKind {
        case .therapy: "Open session detail"
        case .tms: "Complete post-session check-in"
        case .psychiatry, .other: "Back to appointments"
        }
    }

    private func finish() {
        guard clock.finish() else { return }
        _ = state.finishAppointmentRecording(durationSeconds: clock.elapsedSeconds)
    }

    private func close() {
        navigation.dismissPresentedFlow()
        navigation.navigate(to: .appointments)
    }

    private func clearMalformedRecording() {
        guard case .recording = state.appointmentRecording else { return }
        let selected = state.selectedAppointmentKind
        state.selectAppointmentKind(selected == .therapy ? .other : .therapy)
        state.selectAppointmentKind(selected)
    }

    private func openSavedDestination() {
        navigation.dismissPresentedFlow()
        switch state.selectedAppointmentKind {
        case .therapy: navigation.navigate(to: .therapySession)
        case .tms: navigation.navigate(to: .tmsPost)
        case .psychiatry, .other: navigation.navigate(to: .appointments)
        }
    }
}
