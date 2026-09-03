import SwiftUI

enum VoiceJournalPhase: Equatable, Sendable {
    case ready
    case recording
    case stopping
    case saved
    case denied
    case failed
}

struct VoiceJournalView: View {
    @Bindable var navigation: NavigationModel
    @Bindable var state: DemoState
    @State private var phase: VoiceJournalPhase = .ready
    @State private var savedEntry: JournalEntry?

    var body: some View {
        Group {
            switch phase {
            case .ready: permissionView
            case .recording, .stopping: recordingView
            case .saved: savedView
            case .denied: deniedView
            case .failed: failureView
            }
        }
        .background(DesignTokens.canvas.ignoresSafeArea())
        .onChange(of: state.journals) { _, journals in
            guard phase == .recording,
                  let recording = state.latestRecording,
                  let entry = journals.first(where: { $0.audioAttachmentID == recording.attachment.id }) else { return }
            savedEntry = entry
            phase = .saved
        }
        .onChange(of: state.operationError) { _, message in
            if phase == .recording, message != nil, state.recordingSnapshot.isRecording == false {
                phase = .failed
            }
        }
    }

    private var permissionView: some View {
        ScreenLayout(
            title: "Talk it out",
            subtitle: "Your original audio is saved on this device before anything else happens.",
            backAction: navigation.backAction(for: .journalVoice),
            bottomInset: DesignTokens.Spacing.section
        ) {
            StatusNotice(
                title: "Microphone access",
                detail: "Candy Corn asks only when you tap Talk. Nothing is sent anywhere.",
                kind: .information
            )
            Button("Talk", action: start)
                .buttonStyle(PrimaryButtonStyle())
        }
    }

    private var recordingView: some View {
        VStack(spacing: DesignTokens.Spacing.large) {
            HStack {
                Button(action: leaveRecording) {
                    Image(systemName: AppIcon.close.rawValue)
                        .frame(width: DesignTokens.controlMinimum, height: DesignTokens.controlMinimum)
                }
                .foregroundStyle(DesignTokens.cocoa)
                .accessibilityLabel("Dismiss voice journal")
                Spacer()
            }
            Text("What’s going on?").font(TypeScale.question)
            Spacer(minLength: DesignTokens.Spacing.large)
            Text("Recording").font(TypeScale.bodyMedium)
            Text(Self.format(milliseconds: state.recordingSnapshot.elapsedMilliseconds))
                .font(TypeScale.timer).monospacedDigit()
            JournalWaveform(level: state.recordingSnapshot.normalizedLevel)
                .frame(height: 120)
            Button(phase == .stopping ? "Saving" : "Stop") { stop(reason: .user) }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(phase == .stopping)
            Spacer(minLength: DesignTokens.Spacing.large)
            Text("Saved on this device").font(TypeScale.provenance).foregroundStyle(DesignTokens.cocoaSoft)
        }
        .padding(.horizontal, DesignTokens.screenInset)
        .padding(.bottom, DesignTokens.Spacing.section)
    }

    private var savedView: some View {
        ScreenLayout(
            title: state.latestRecording?.stopReason == .interruption ? "Recording stopped" : "Saved on this device",
            subtitle: "Your original audio is available for playback.",
            backAction: navigation.backAction(for: .journalVoice)
        ) {
            if let attachment = state.latestRecording?.attachment {
                Button {
                    Task { try? await state.dependencies.playback.play(attachment: attachment) }
                } label: {
                    Label("Play original audio", systemImage: AppIcon.play.rawValue)
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            if let savedEntry {
                ProvenanceLine(provenance: savedEntry.provenance)
            }
            Button("View in history") {
                navigation.goBack(from: .journalVoice)
                navigation.navigate(to: .history)
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    private var deniedView: some View {
        ScreenLayout(title: "Microphone access is off", backAction: navigation.backAction(for: .journalVoice)) {
            StatusNotice(title: "Recording did not start", detail: "Enable microphone access in Settings, then try again. Your existing journals are unchanged.", kind: .warning)
            Button("Try again", action: start).buttonStyle(SecondaryButtonStyle())
        }
    }

    private var failureView: some View {
        ScreenLayout(title: "Recording could not start", backAction: navigation.backAction(for: .journalVoice)) {
            if state.latestRecording == nil {
                StatusNotice(title: "Nothing was saved", detail: "No valid audio file was created. Your existing journals are unchanged.", kind: .warning)
            } else {
                StatusNotice(title: "Recording saved", detail: state.operationError ?? "The original audio was finalized, but the journal details could not be saved.", kind: .warning)
            }
            Button("Try again", action: start).buttonStyle(SecondaryButtonStyle())
        }
    }

    private func start() {
        guard phase != .recording else { return }
        Task {
            let status = await state.dependencies.recording.authorizationStatus()
            let started = await state.startRecording(kind: .journal)
            if started {
                phase = .recording
            } else {
                phase = status == .denied || status == .restricted ? .denied : .failed
            }
        }
    }

    private func stop(reason: RecordingStopReason) {
        guard phase == .recording else { return }
        phase = .stopping
        Task {
            guard let recording = await state.stopRecording(reason: reason) else {
                phase = .failed
                return
            }
            savedEntry = await state.createJournal(rawText: "", inputType: .voice, attachmentID: recording.attachment.id)
            phase = savedEntry == nil ? .failed : .saved
        }
    }

    private func leaveRecording() {
        guard phase == .recording else {
            navigation.goBack(from: .journalVoice)
            return
        }
        phase = .stopping
        Task {
            if let recording = await state.stopRecording(reason: .user) {
                _ = await state.createJournal(rawText: "", inputType: .voice, attachmentID: recording.attachment.id)
            }
            navigation.goBack(from: .journalVoice)
        }
    }

    static func format(milliseconds: Int) -> String {
        let seconds = max(0, milliseconds / 1_000)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
