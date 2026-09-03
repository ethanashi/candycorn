import SwiftUI

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
                Text(speakerName(segment.speaker))
                    .font(TypeScale.label)
                    .fontWeight(.semibold)
                    .tracking(0)
                Button {
                    onTimestamp(segment)
                } label: {
                    Text(AppointmentRecordingClock.format(milliseconds: segment.startMilliseconds))
                    .font(TypeScale.provenance)
                    .tracking(0)
                    .monospacedDigit()
                }
                .buttonStyle(.plain)
                .frame(minHeight: DesignTokens.controlMinimum)
                .accessibilityLabel("Play from \(AppointmentRecordingClock.format(milliseconds: segment.startMilliseconds))")
                Spacer()
            }
            Text(segment.text)
                .font(Font.custom("AvenirNext-Regular", size: 15, relativeTo: .body))
                .tracking(0)
                .foregroundStyle(DesignTokens.cocoa)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            provenance(segment)
            if showsCorrections, segment.rawSpeakerLabel != nil {
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

    private func provenance(_ segment: TranscriptSegment) -> some View {
        ProvenanceInline(
            voice: segment.speaker == .provider ? .provider : .user,
            text: provenanceText(segment)
        )
    }

    private func speakerName(_ speaker: TranscriptSegment.Speaker) -> String {
        switch speaker {
        case .patient: patientName
        case .provider: providerName
        case .unknown: "Unknown speaker"
        }
    }

    private func provenanceText(_ segment: TranscriptSegment) -> String {
        let time = AppointmentRecordingClock.format(milliseconds: segment.startMilliseconds)
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
