import SwiftUI

enum TherapySessionTab: String, CaseIterable, Sendable {
    case summary = "Summary"
    case transcript = "Transcript"
    case homework = "Homework"
    case talkingPoints = "Talking points"
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
    @AccessibilityFocusState private var focusedSegmentID: UUID?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.large) {
                    header
                    UnderlinePicker(options: TherapySessionTab.allCases, selection: $selection) { $0.rawValue }
                    panel
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DesignTokens.screenInset)
                .padding(.top, DesignTokens.Spacing.compact)
                .padding(.bottom, 260)
            }
            .background(DesignTokens.canvas.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                PlaybackScrubber()
                    .padding(.horizontal, DesignTokens.screenInset)
                    .padding(.bottom, 82)
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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Button {
                navigation.navigate(to: .appointments)
            } label: {
                Image(systemName: AppIcon.back.rawValue)
                    .frame(width: DesignTokens.controlMinimum, height: DesignTokens.controlMinimum, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to appointments")
            Text("Therapy with Dr. Elena Park")
                .font(TypeScale.pageTitle)
                .fixedSize(horizontal: false, vertical: true)
            Text("Sep 2 · 52 min · Saved on this device")
                .font(TypeScale.body)
                .foregroundStyle(DesignTokens.cocoaSoft)
                .monospacedDigit()
        }
        .foregroundStyle(DesignTokens.cocoa)
    }

    @ViewBuilder private var panel: some View {
        switch selection {
        case .summary: summaryPanel
        case .transcript: transcriptPanel
        case .homework: homeworkPanel
        case .talkingPoints: talkingPointsPanel
        }
    }

    private var summaryPanel: some View {
        VStack(spacing: 0) {
            ForEach(TherapySummaryEvidence.items) { item in
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
        LazyVStack(spacing: 0) {
            ForEach(state.transcript) { segment in
                TranscriptRow(
                    segment: segment,
                    speaker: state.speakerCorrections[segment.id] ?? segment.speaker,
                    correct: { speaker in _ = state.correctSpeaker(segmentID: segment.id, to: speaker) }
                )
                .id(segment.id)
                .accessibilityFocused($focusedSegmentID, equals: segment.id)
            }
        }
        .accessibilityLabel("Source-preserving transcript")
    }

    private var homeworkPanel: some View {
        CareLedger(items: [
            CareLedgerItem(
                text: "Finish the senior-year football timeline.",
                provenance: providerProvenance
            ),
            CareLedgerItem(
                text: "Notice when feeling better is followed by guilt about moving forward.",
                provenance: providerProvenance
            ),
        ])
    }

    private var talkingPointsPanel: some View {
        CareLedger(items: [
            CareLedgerItem(
                text: "The senior-year meeting with the coaches.",
                provenance: Provenance(voice: .user, label: "You brought this up", detail: "Therapy, Sep 2 at 38:44", occurredAt: nil, sourceRoute: .therapySession)
            ),
            CareLedgerItem(
                text: "Ask whether needing proof is the part that keeps the memory stuck.",
                provenance: Provenance(voice: .candyCorn, label: "Candy Corn suggested this", detail: "Based on the saved transcript. You chose to keep it.", occurredAt: nil, sourceRoute: .therapySession)
            ),
        ])
    }

    private var providerProvenance: Provenance {
        Provenance(voice: .provider, label: "Therapist assigned this", detail: "Therapy, Sep 2 at 42:18", occurredAt: nil, sourceRoute: .therapySession)
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
        case .patient: DesignTokens.orangePressed
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
                .accessibilityLabel("Simulated playback position")
            Text("Playing from the saved transcript")
                .font(TypeScale.bodyMedium)
        }
        .padding(DesignTokens.Spacing.base)
        .background(DesignTokens.surface)
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous).stroke(DesignTokens.hairline))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous))
        .shadow(color: DesignTokens.cocoa.opacity(0.06), radius: 8, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Simulated transcript playback")
    }
}
