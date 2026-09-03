import SwiftUI

struct SessionTranscriptView: View {
    let segments: [TranscriptSegment]
    let isRelabeling: (TranscriptSegment) -> Bool
    let onLabel: (TranscriptSegment, TranscriptSegment.Speaker) -> Void
    let onTimestamp: (TranscriptSegment) -> Void

    init(
        segments: [TranscriptSegment],
        isRelabeling: @escaping (TranscriptSegment) -> Bool,
        onLabel: @escaping (TranscriptSegment, TranscriptSegment.Speaker) -> Void,
        onTimestamp: @escaping (TranscriptSegment) -> Void = { _ in }
    ) {
        self.segments = segments
        self.isRelabeling = isRelabeling
        self.onLabel = onLabel
        self.onTimestamp = onTimestamp
    }

    var body: some View {
        if segments.isEmpty {
            StatusNotice(
                title: "No transcript yet",
                detail: "The original recording remains saved on this device.",
                kind: .information
            )
        } else {
            LazyVStack(spacing: 0) {
                ForEach(segments.sorted(by: Self.order)) { segment in
                    row(segment)
                }
            }
            .accessibilityLabel("Source-preserving transcript")
        }
    }

    private func row(_ segment: TranscriptSegment) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            HStack(spacing: DesignTokens.Spacing.small) {
                speakerGlyph(segment.speaker)
                Text(speakerName(segment.speaker))
                    .font(TypeScale.label)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    onTimestamp(segment)
                } label: {
                    Label(
                        AppointmentRecordingClock.format(milliseconds: segment.startMilliseconds),
                        systemImage: AppIcon.play.rawValue
                    )
                    .font(TypeScale.provenance)
                    .monospacedDigit()
                }
                .buttonStyle(.plain)
                .frame(minHeight: DesignTokens.controlMinimum)
                .accessibilityLabel("Play from \(AppointmentRecordingClock.format(milliseconds: segment.startMilliseconds))")
            }
            Text(segment.text)
                .font(TypeScale.body)
                .foregroundStyle(DesignTokens.cocoa)
                .fixedSize(horizontal: false, vertical: true)
            if segment.rawSpeakerLabel != nil {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: DesignTokens.Spacing.small) { labelButtons(segment) }
                    VStack(spacing: DesignTokens.Spacing.small) { labelButtons(segment) }
                }
                .disabled(isRelabeling(segment))
            }
        }
        .foregroundStyle(DesignTokens.cocoa)
        .padding(.vertical, DesignTokens.Spacing.base)
        .overlay(alignment: .bottom) { Divider().overlay(DesignTokens.hairline) }
    }

    @ViewBuilder private func labelButtons(_ segment: TranscriptSegment) -> some View {
        Button("Mark as me") { onLabel(segment, .patient) }
            .buttonStyle(SecondaryButtonStyle())
        Button("Mark as provider") { onLabel(segment, .provider) }
            .buttonStyle(SecondaryButtonStyle())
    }

    @ViewBuilder private func speakerGlyph(_ speaker: TranscriptSegment.Speaker) -> some View {
        if speaker == .unknown {
            Image(systemName: AppIcon.questionmark.rawValue)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
        } else {
            KernelGlyph(voice: speaker == .provider ? .provider : .user, height: 18, decorative: true)
        }
    }

    private func speakerName(_ speaker: TranscriptSegment.Speaker) -> String {
        switch speaker {
        case .patient: "You"
        case .provider: "Provider"
        case .unknown: "Unknown speaker"
        }
    }

    private static func order(_ lhs: TranscriptSegment, _ rhs: TranscriptSegment) -> Bool {
        (lhs.startMilliseconds, lhs.id.uuidString) < (rhs.startMilliseconds, rhs.id.uuidString)
    }
}
