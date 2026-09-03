import SwiftUI

struct SessionProcessingStatusView: View {
    let record: SessionProcessingRecord?
    let onReviewSummary: () -> Void
    let onRetry: () -> Void
    let onOpenDebrief: () -> Void

    var body: some View {
        V2Card(background: background) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
                HStack(alignment: .top, spacing: DesignTokens.Spacing.compact) {
                    IconTile(icon: icon)
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xSmall) {
                        Text(title).font(TypeScale.rowTitle)
                        Text(detail)
                            .font(TypeScale.meta)
                            .foregroundStyle(DesignTokens.cocoaSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let progress = record?.progress, record?.stage != .ready {
                    ProgressView(value: progress)
                        .tint(DesignTokens.orange)
                        .accessibilityLabel(title)
                }
                action
            }
        }
    }

    @ViewBuilder private var action: some View {
        if record?.failure?.code == .summaryPermissionRequired {
            Button("Review what leaves this device", action: onReviewSummary)
                .buttonStyle(SecondaryButtonStyle())
        } else if record?.failure != nil {
            Button("Retry", action: onRetry).buttonStyle(SecondaryButtonStyle())
        } else if record?.stage == .ready,
                  Route(rawValue: "/sessions/therapy-sep-2/debrief") != nil {
            Button("Open debrief", action: onOpenDebrief).buttonStyle(PrimaryButtonStyle())
        }
    }

    private var title: String {
        guard let record else { return "Recording saved" }
        if let failure = record.failure, failure.code != .summaryPermissionRequired {
            return "Processing paused"
        }
        return switch record.stage {
        case .recordingSaved: "Recording saved"
        case .transcribing: "Transcribing on this device"
        case .separatingSpeakers: "Separating speakers on this device"
        case .summarizing where record.failure?.code == .summaryPermissionRequired: "Ready to make the debrief"
        case .summarizing: "Creating your debrief"
        case .ready: "Transcript and debrief ready"
        }
    }

    private var detail: String {
        if let failure = record?.failure { return failure.message }
        return switch record?.stage {
        case .recordingSaved, nil: "Your original recording stays on this device."
        case .transcribing: "The saved recording is being transcribed locally."
        case .separatingSpeakers: "Speaker turns are being matched locally."
        case .summarizing: "Only the reviewed transcript text is sent after you approve it."
        case .ready: "The original recording and transcript remain available."
        }
    }

    private var icon: AppIcon {
        record?.stage == .ready ? .checkCircle : .waveform
    }

    private var background: Color {
        record?.failure != nil && record?.failure?.code != .summaryPermissionRequired
            ? DesignTokens.surface : DesignTokens.surfaceWarm
    }
}
