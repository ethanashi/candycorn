import SwiftUI

struct JournalRecordingState: Equatable, Sendable {
    static let initialSeconds = 137

    private(set) var elapsedSeconds: Int
    private(set) var isRecording: Bool

    init(elapsedSeconds: Int = Self.initialSeconds, isRecording: Bool = true) {
        self.elapsedSeconds = max(0, elapsedSeconds)
        self.isRecording = isRecording
    }

    mutating func tick() {
        guard isRecording, elapsedSeconds < 86_400 else { return }
        elapsedSeconds += 1
    }

    @discardableResult
    mutating func stop() -> Bool {
        guard isRecording else { return false }
        isRecording = false
        return true
    }

    static func format(seconds: Int) -> String {
        guard seconds >= 0 else { return "00:00" }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

struct VoiceJournalView: View {
    @Bindable var navigation: NavigationModel
    @State private var recording = JournalRecordingState()

    var body: some View {
        Group {
            if recording.isRecording {
                recordingView
            } else {
                savedView
            }
        }
        .background(DesignTokens.canvas.ignoresSafeArea())
        .task(id: recording.isRecording) {
            guard recording.isRecording else { return }
            for _ in 0..<86_400 {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
                guard recording.isRecording, !Task.isCancelled else { return }
                recording.tick()
            }
        }
    }

    private var recordingView: some View {
        VStack(spacing: 0) {
            HStack {
                cancelButton(iconOnly: true)
                Spacer()
                cancelButton(iconOnly: false)
            }

            VStack(spacing: DesignTokens.Spacing.small) {
                Text("What’s going on?")
                    .font(TypeScale.question)
                Text("Private journal recording")
                    .font(TypeScale.label)
                    .foregroundStyle(DesignTokens.cocoaSoft)
            }
            .multilineTextAlignment(.center)
            .padding(.top, DesignTokens.Spacing.small)

            Spacer(minLength: DesignTokens.Spacing.generous)

            VStack(spacing: DesignTokens.Spacing.compact) {
                Text("Simulated recording")
                    .font(TypeScale.bodyMedium)
                Text(JournalRecordingState.format(seconds: recording.elapsedSeconds))
                    .font(TypeScale.timer)
                    .monospacedDigit()
                    .accessibilityLabel("Recording duration")
                    .accessibilityValue(JournalRecordingState.format(seconds: recording.elapsedSeconds))
            }

            JournalWaveform(phase: recording.elapsedSeconds)
                .padding(.vertical, DesignTokens.Spacing.section)

            Button {
                _ = recording.stop()
            } label: {
                Label("Stop", systemImage: AppIcon.stop.rawValue)
                    .font(TypeScale.button)
                    .foregroundStyle(.white)
                    .frame(minWidth: 112, minHeight: DesignTokens.primaryButtonHeight)
                    .padding(.horizontal, DesignTokens.Spacing.base)
                    .background(DesignTokens.orange)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.controlRadius, style: .continuous))
            }
            .buttonStyle(.plain)

            Spacer(minLength: DesignTokens.Spacing.generous)

            Text("No microphone is used. This recording is simulated on this device.")
                .font(TypeScale.provenance)
                .foregroundStyle(DesignTokens.cocoaSoft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 310)
        }
        .foregroundStyle(DesignTokens.cocoa)
        .padding(.horizontal, DesignTokens.screenInset)
        .padding(.top, DesignTokens.Spacing.xSmall)
        .padding(.bottom, DesignTokens.Spacing.section)
    }

    private var savedView: some View {
        ScreenLayout(
            title: "Saved on this device",
            subtitle: "This is a simulated journal. No audio was recorded.",
            backAction: cancel,
            bottomInset: DesignTokens.Spacing.section
        ) {
            HStack(spacing: DesignTokens.Spacing.compact) {
                KernelGlyph(voice: .user, height: 20)
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xSmall) {
                    Text(JournalRecordingState.format(seconds: recording.elapsedSeconds))
                        .font(TypeScale.section)
                        .monospacedDigit()
                    Text("Voice journal, Sep 5")
                        .font(TypeScale.provenance)
                        .foregroundStyle(DesignTokens.cocoaSoft)
                }
                Spacer()
                Image(systemName: AppIcon.play.rawValue)
                    .frame(width: DesignTokens.controlMinimum, height: DesignTokens.controlMinimum)
                    .overlay(Circle().stroke(DesignTokens.hairline, lineWidth: 1))
                    .accessibilityLabel("Play simulated audio")
            }
            .padding(DesignTokens.Spacing.base)
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous).stroke(DesignTokens.hairline, lineWidth: 1))

            VStack(spacing: DesignTokens.Spacing.compact) {
                Button("Transcribe") { open(.journalDetail) }
                    .buttonStyle(PrimaryButtonStyle())
                Button("Keep audio only") { open(.history) }
                    .buttonStyle(SecondaryButtonStyle())
            }

            Text("Nothing is sent anywhere. Later phases can connect this choice to on-device recording.")
                .font(TypeScale.provenance)
                .foregroundStyle(DesignTokens.cocoaSoft)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func cancelButton(iconOnly: Bool) -> some View {
        Button(action: cancel) {
            if iconOnly {
                Image(systemName: AppIcon.close.rawValue)
                    .frame(width: DesignTokens.controlMinimum, height: DesignTokens.controlMinimum)
            } else {
                Text("Cancel")
                    .font(TypeScale.bodyMedium)
                    .frame(minWidth: DesignTokens.controlMinimum, minHeight: DesignTokens.controlMinimum)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cancel recording")
    }

    private func cancel() {
        navigation.dismissPresentedFlow()
    }

    private func open(_ route: Route) {
        navigation.dismissPresentedFlow()
        navigation.navigate(to: route)
    }
}
