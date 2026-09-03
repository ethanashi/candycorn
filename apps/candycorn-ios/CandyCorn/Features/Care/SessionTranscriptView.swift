import SwiftUI

/// Source-preserving transcript as one v2 card of speaker turns.
struct SessionTranscriptView: View {
    let segments: [TranscriptSegment]
    let patientName: String
    let providerName: String
    let providerRole: String
    let sessionDate: String?
    let showsCorrections: Bool
    let isRelabeling: (TranscriptSegment) -> Bool
    let onLabel: (TranscriptSegment, TranscriptSegment.Speaker) -> Void
    let onTimestamp: (TranscriptSegment) -> Void

    init(
        segments: [TranscriptSegment],
        patientName: String = "You",
        providerName: String = "Provider",
        providerRole: String = "Provider",
        sessionDate: String? = nil,
        showsCorrections: Bool = true,
        isRelabeling: @escaping (TranscriptSegment) -> Bool,
        onLabel: @escaping (TranscriptSegment, TranscriptSegment.Speaker) -> Void,
        onTimestamp: @escaping (TranscriptSegment) -> Void = { _ in }
    ) {
        self.segments = segments
        self.patientName = patientName
        self.providerName = providerName
        self.providerRole = providerRole
        self.sessionDate = sessionDate
        self.showsCorrections = showsCorrections
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
            V2Card(padding: 0) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(segments.sorted(by: Self.order).enumerated()), id: \.element.id) { index, segment in
                        row(segment, divider: index > 0)
                    }
                }
            }
            .accessibilityLabel("Source-preserving transcript")
        }
    }

    private func row(_ segment: TranscriptSegment, divider: Bool) -> some View {
        let time = AppointmentRecordingClock.format(milliseconds: segment.startMilliseconds)
        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            HStack(spacing: DesignTokens.Spacing.small) {
                speakerGlyph(segment.speaker)
                Text(speakerName(segment.speaker))
                    .font(TypeScale.metaStrong)
                    .foregroundStyle(DesignTokens.cocoa)
                    .lineLimit(1)
                Spacer(minLength: DesignTokens.Spacing.small)
                Button {
                    onTimestamp(segment)
                } label: {
                    HStack(spacing: 4) {
                        AppIcon.play.image.font(.system(size: 10, weight: .bold))
                        Text(time)
                            .font(TypeScale.metaStrong)
                            .monospacedDigit()
                    }
                    .foregroundStyle(DesignTokens.orangePressed)
                    .frame(minHeight: DesignTokens.controlMinimum)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play from \(time)")
            }
            Text(segment.text)
                .font(TypeScale.body)
                .foregroundStyle(DesignTokens.cocoa)
                .fixedSize(horizontal: false, vertical: true)
            ProvenanceInline(
                voice: segment.speaker == .provider ? .provider : .user,
                text: provenanceText(segment, time: time)
            )
            if showsCorrections, segment.rawSpeakerLabel != nil {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: DesignTokens.Spacing.small) { labelButtons(segment) }
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) { labelButtons(segment) }
                }
                .disabled(isRelabeling(segment))
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.base)
        .padding(.vertical, DesignTokens.Spacing.compact)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            if divider {
                Rectangle().fill(DesignTokens.hairline).frame(height: 1).padding(.horizontal, DesignTokens.Spacing.base)
            }
        }
    }

    @ViewBuilder private func labelButtons(_ segment: TranscriptSegment) -> some View {
        Button("Mark as me") { onLabel(segment, .patient) }
            .buttonStyle(CompactGhostButtonStyle())
        Button("Mark as provider") { onLabel(segment, .provider) }
            .buttonStyle(CompactGhostButtonStyle())
    }

    @ViewBuilder private func speakerGlyph(_ speaker: TranscriptSegment.Speaker) -> some View {
        if speaker == .unknown {
            AppIcon.questionmark.image
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DesignTokens.cocoaSoft)
                .frame(width: 14, height: 14)
                .accessibilityHidden(true)
        } else {
            KernelGlyph(voice: speaker == .provider ? .provider : .user, height: 14, decorative: true)
        }
    }

    private func speakerName(_ speaker: TranscriptSegment.Speaker) -> String {
        switch speaker {
        case .patient: patientName
        case .provider: providerName
        case .unknown: "Unknown speaker"
        }
    }

    private func provenanceText(_ segment: TranscriptSegment, time: String) -> String {
        switch segment.speaker {
        case .patient:
            return "You said this at \(time)"
        case .provider:
            let date = sessionDate.map { " on \($0)" } ?? ""
            return "\(providerRole) said this\(date) at \(time)"
        case .unknown:
            return "Speaker not confirmed at \(time)"
        }
    }

    private static func order(_ lhs: TranscriptSegment, _ rhs: TranscriptSegment) -> Bool {
        (lhs.startMilliseconds, lhs.id.uuidString) < (rhs.startMilliseconds, rhs.id.uuidString)
    }
}
