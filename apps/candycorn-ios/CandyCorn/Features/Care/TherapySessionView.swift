import SwiftUI

enum TherapySessionTab: String, CaseIterable, Sendable {
    case summary = "Summary"
    case transcript = "Transcript"
    case homework = "Homework"
    case talkingPoints = "Talking points"
    case notes = "Notes"
}

struct TherapySummaryEvidence: Identifiable, Equatable, Sendable {
    let id: UUID
    let text: String
    let voice: ProvenanceVoice
    let source: String

    static let items: [TherapySummaryEvidence] = [
        TherapySummaryEvidence(
            id: SeededData.transcript[0].id,
            text: "The missed chance to prove you could have played still feels more important than playing again.",
            voice: .user,
            source: "You said this at 12:24"
        ),
        TherapySummaryEvidence(
            id: SeededData.transcript[1].id,
            text: "Dr. Park reflected that the grief may be about never getting to test what you believed about yourself.",
            voice: .provider,
            source: "Therapist said this on Sep 2 at 12:48"
        ),
    ]

    static func segment(for evidenceID: UUID, in transcript: [TranscriptSegment]) -> TranscriptSegment? {
        transcript.first { $0.id == evidenceID }
    }
}

struct TherapySessionView: View {
    @Bindable var navigation: NavigationModel
    @Bindable var state: DemoState
    @State private var selection = TherapySessionTab.transcript
    @State private var pendingEvidenceID: UUID?
    @State private var notes = ""
    @AccessibilityFocusState private var focusedSegmentID: UUID?

    @ViewBuilder
    var body: some View {
        if sessionAppointment == nil {
            ScreenLayout(
                title: "Therapy session",
                subtitle: "Saved sessions appear here.",
                backAction: navigation.backAction(for: .therapySession)
            ) {
                StatusNotice(title: "No saved therapy session", detail: "Record an appointment or add manual notes first.", kind: .information)
            }
        } else {
            sessionContent
        }
    }

    private var sessionContent: some View {
        ScrollViewReader { proxy in
            ScreenLayout(
                title: "Therapy with \(sessionAppointment?.providerName ?? "your provider")",
                subtitle: sessionMetadata,
                backAction: navigation.backAction(for: .therapySession),
                bottomInset: 260
            ) {
                UnderlinePicker(options: TherapySessionTab.allCases, selection: $selection) { $0.rawValue }
                panel
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if sessionAppointment?.recordingAttachmentID != nil {
                    PlaybackScrubber(onPlay: playRecording)
                        .padding(.horizontal, DesignTokens.screenInset)
                        .padding(.bottom, 82)
                }
            }
            .onChange(of: selection) { _, tab in
                guard tab == .transcript, let id = pendingEvidenceID else { return }
                Task { @MainActor in
                    await Task.yield()
                    proxy.scrollTo(id, anchor: .center)
                    focusedSegmentID = id
                    pendingEvidenceID = nil
                }
            }
        }
        .onAppear { notes = sessionAppointment?.manualNotes ?? "" }
    }

    @ViewBuilder private var panel: some View {
        switch selection {
        case .summary: summaryPanel
        case .transcript: transcriptPanel
        case .homework: homeworkPanel
        case .talkingPoints: talkingPointsPanel
        case .notes: notesPanel
        }
    }

    private var summaryPanel: some View {
        VStack(spacing: 0) {
            if summaryEvidence.isEmpty {
                StatusNotice(title: "No summary", detail: "The original recording and your manual notes remain available.", kind: .information)
            }
            ForEach(summaryEvidence) { item in
                HStack(alignment: .top, spacing: DesignTokens.Spacing.compact) {
                    KernelGlyph(voice: item.voice, height: 18, decorative: true).padding(.top, 3)
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xSmall) {
                        Text(item.text).font(TypeScale.body).fixedSize(horizontal: false, vertical: true)
                        Button(item.source) { openEvidence(item.id) }
                            .font(TypeScale.provenance)
                            .foregroundStyle(DesignTokens.cocoaSoft)
                            .underline()
                            .frame(minHeight: DesignTokens.controlMinimum)
                    }
                }
                .padding(.vertical, DesignTokens.Spacing.base)
                .overlay(alignment: .bottom) { Divider().overlay(DesignTokens.hairline) }
            }
        }
    }

    private var transcriptPanel: some View {
        Group {
            if sessionTranscript.isEmpty {
                StatusNotice(title: "No transcript", detail: "The original recording and your manual notes are available. Transcription is not part of this version.", kind: .information)
            } else {
                LazyVStack(spacing: 0) {
            ForEach(sessionTranscript) { segment in
                TranscriptRow(
                    segment: segment,
                    speaker: state.speakerCorrections[segment.id] ?? segment.speaker,
                    correct: { speaker in _ = state.correctSpeaker(segmentID: segment.id, to: speaker) }
                )
                .id(segment.id)
                .accessibilityFocused($focusedSegmentID, equals: segment.id)
            }
                }
        }
        }
        .accessibilityLabel("Source-preserving transcript")
    }

    private var homeworkPanel: some View {
        CareLedger(items: state.goals.filter { $0.sourceEntityID == sessionAppointment?.id }.map {
            CareLedgerItem(text: $0.title, provenance: $0.provenance)
        })
    }

    private var talkingPointsPanel: some View {
        CareLedger(items: state.talkingPoints.filter { $0.sourceID == sessionAppointment?.id }.map {
            CareLedgerItem(text: $0.text, provenance: $0.provenance)
        })
    }

    private var notesPanel: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.base) {
            Text("Manual notes").font(TypeScale.sectionCompact)
            TextEditor(text: $notes)
                .font(TypeScale.body)
                .frame(minHeight: 220)
                .overlay(RoundedRectangle(cornerRadius: DesignTokens.controlRadius).stroke(DesignTokens.hairline))
            Button("Save notes") {
                guard var appointment = sessionAppointment else { return }
                appointment.manualNotes = String(notes.prefix(4_000))
                Task { _ = await state.saveAppointment(appointment) }
            }
            .buttonStyle(PrimaryButtonStyle())
            Button("Add to next appointment") {
                Task { _ = await state.createTalkingPoint(text: notes, source: .session, sourceID: sessionAppointment?.id) }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var sessionAppointment: Appointment? {
        if let id = state.selectedAppointmentID,
           let selected = state.appointments.first(where: { $0.id == id && $0.kind == .therapy && $0.status == .completed }) {
            return selected
        }
        return state.appointments.filter { $0.kind == .therapy && $0.status == .completed }.max {
            ($0.startedAt ?? .distantPast) < ($1.startedAt ?? .distantPast)
        }
    }

    private var sessionTranscript: [TranscriptSegment] {
        guard let id = sessionAppointment?.id else { return [] }
        return state.transcript.filter { $0.appointmentID == id }
    }

    private var summaryEvidence: [TherapySummaryEvidence] {
        guard let id = sessionAppointment?.id,
              state.artifacts.contains(where: { $0.kind == .sessionSummary && $0.sourceIDs.contains(id) }) else { return [] }
        return TherapySummaryEvidence.items.filter { TherapySummaryEvidence.segment(for: $0.id, in: sessionTranscript) != nil }
    }

    private var sessionMetadata: String {
        guard let appointment = sessionAppointment else { return "Saved on this device" }
        let date = (appointment.startedAt ?? appointment.scheduledAt)?.formatted(.dateTime.month(.abbreviated).day()) ?? "Date not recorded"
        let duration: String
        if let start = appointment.startedAt, let end = appointment.endedAt {
            duration = "\(max(0, Int(end.timeIntervalSince(start) / 60))) min"
        } else {
            duration = "Duration not recorded"
        }
        return "\(date) · \(duration) · Saved on this device"
    }

    private func playRecording() {
        guard let id = sessionAppointment?.recordingAttachmentID,
              let attachment = state.attachments.first(where: { $0.id == id }) else { return }
        Task { try? await state.dependencies.playback.play(attachment: attachment) }
    }

    private func openEvidence(_ id: UUID) {
        guard TherapySummaryEvidence.segment(for: id, in: state.transcript) != nil else { return }
        pendingEvidenceID = id
        selection = .transcript
    }
}

private struct TranscriptRow: View {
    let segment: TranscriptSegment
    let speaker: TranscriptSegment.Speaker
    let correct: (TranscriptSegment.Speaker) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            HStack(spacing: DesignTokens.Spacing.small) {
                speakerGlyph
                Text(speakerName)
                    .font(TypeScale.label)
                    .fontWeight(.semibold)
                    .foregroundStyle(speakerColor)
                Spacer()
                Text(AppointmentRecordingClock.format(milliseconds: segment.startMilliseconds))
                    .font(TypeScale.provenance)
                    .foregroundStyle(DesignTokens.cocoaSoft)
                    .monospacedDigit()
            }
            Text(segment.text)
                .font(TypeScale.body)
                .foregroundStyle(DesignTokens.cocoa)
                .fixedSize(horizontal: false, vertical: true)
            if speaker == .unknown { correctionButtons }
        }
        .padding(.vertical, DesignTokens.Spacing.base)
        .overlay(alignment: .bottom) { Divider().overlay(DesignTokens.hairline) }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var speakerGlyph: some View {
        if speaker == .unknown {
            Text("?")
                .font(TypeScale.provenance)
                .foregroundStyle(DesignTokens.cocoaSoft)
                .frame(width: 16, height: 20)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(DesignTokens.cocoaSoft))
                .accessibilityHidden(true)
        } else {
            KernelGlyph(voice: speaker == .provider ? .provider : .user, height: 18, decorative: true)
        }
    }

    private var correctionButtons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DesignTokens.Spacing.small) { correctionButtonContent }
            VStack(spacing: DesignTokens.Spacing.small) { correctionButtonContent }
        }
        .padding(.top, DesignTokens.Spacing.xSmall)
    }

    @ViewBuilder private var correctionButtonContent: some View {
        Button("Mark as me") { correct(.patient) }.buttonStyle(SecondaryButtonStyle())
        Button("Mark as provider") { correct(.provider) }.buttonStyle(SecondaryButtonStyle())
    }

    private var speakerName: String {
        switch speaker {
        case .patient: "Jamie"
        case .provider: "Dr. Elena Park"
        case .unknown: "Unknown speaker"
        }
    }

    private var speakerColor: Color {
        switch speaker {
        case .patient: DesignTokens.cocoa
        case .provider: DesignTokens.cocoa
        case .unknown: DesignTokens.cocoaSoft
        }
    }
}

private struct CareLedgerItem: Identifiable {
    let text: String
    let provenance: Provenance
    var id: String { text }
}

private struct CareLedger: View {
    let items: [CareLedgerItem]

    var body: some View {
        VStack(spacing: 0) {
            if items.isEmpty {
                Text("Nothing saved here yet.")
                    .font(TypeScale.label)
                    .foregroundStyle(DesignTokens.cocoaSoft)
                    .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            }
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
                    Text(item.text).font(TypeScale.body).fixedSize(horizontal: false, vertical: true)
                    ProvenanceLine(provenance: item.provenance)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, DesignTokens.Spacing.base)
                .overlay(alignment: .bottom) { Divider().overlay(DesignTokens.hairline) }
            }
        }
    }
}

private struct PlaybackScrubber: View {
    let onPlay: () -> Void
    @State private var position = 768.0

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xSmall) {
            HStack {
                Text("12:48")
                Spacer()
                Text("52:06")
            }
            .font(TypeScale.provenance)
            .foregroundStyle(DesignTokens.cocoaSoft)
            .monospacedDigit()
            Slider(value: $position, in: 0...3126)
                .tint(DesignTokens.orange)
                .frame(minHeight: DesignTokens.controlMinimum)
                .accessibilityLabel("Playback position")
            Text("Saved session audio")
                .font(TypeScale.bodyMedium)
            Button("Play recording", action: onPlay)
                .buttonStyle(SecondaryButtonStyle())
        }
        .padding(DesignTokens.Spacing.base)
        .background(DesignTokens.surface)
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous).stroke(DesignTokens.hairline))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous))
        .shadow(color: DesignTokens.cocoa.opacity(0.06), radius: 8, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Transcript playback")
    }
}
