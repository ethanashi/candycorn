import SwiftUI

struct AIProcessingStatusRow: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let detail: String

    var accessibilityLabel: String { "\(title). \(detail)" }
}

enum AIProcessingStatusLogic {
    static func rows(
        mode: AIMode,
        provider: AIProvider,
        hasOpenRouterKey: Bool,
        configuration: AIModelConfiguration
    ) -> [AIProcessingStatusRow] {
        let language = languageStatus(mode: mode, provider: provider, hasOpenRouterKey: hasOpenRouterKey, modelID: configuration.organizerModelID)
        let photo = languageStatus(mode: mode, provider: provider, hasOpenRouterKey: hasOpenRouterKey, modelID: configuration.visionModelID)
        return [
            AIProcessingStatusRow(id: "journal", title: "Journal intelligence", detail: language),
            AIProcessingStatusRow(id: "voice", title: "Voice transcription", detail: "Not yet available"),
            AIProcessingStatusRow(id: "photo", title: "Photo to text", detail: photo),
            AIProcessingStatusRow(id: "upload", title: "Cloud upload", detail: "Only when you tap Send")
        ]
    }

    private static func languageStatus(mode: AIMode, provider: AIProvider, hasOpenRouterKey: Bool, modelID: String) -> String {
        guard mode != .off, provider != .off else { return "Off" }
        guard provider == .router else { return "Not yet available" }
        guard hasOpenRouterKey else { return "Unavailable until you add a router key" }
        return "Cloud (router, \(modelID))"
    }
}

struct AIProcessingStatusView: View {
    let mode: AIMode
    let provider: AIProvider
    let hasOpenRouterKey: Bool
    let configuration: AIModelConfiguration

    private var rows: [AIProcessingStatusRow] {
        AIProcessingStatusLogic.rows(
            mode: mode,
            provider: provider,
            hasOpenRouterKey: hasOpenRouterKey,
            configuration: configuration
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DesignTokens.Spacing.small) {
                KernelGlyph(voice: .candyCorn, height: 18)
                Text("Processing status")
                    .font(TypeScale.sectionCompact)
                    .foregroundStyle(DesignTokens.cocoa)
            }
            .padding(.bottom, DesignTokens.Spacing.compact)

            Divider().overlay(DesignTokens.hairline)
            ForEach(rows) { row in
                statusRow(row)
                if row.id != rows.last?.id {
                    Divider().overlay(DesignTokens.hairline)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Processing status")
    }

    private func statusRow(_ row: AIProcessingStatusRow) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xSmall) {
            Text(row.title)
                .font(TypeScale.bodyMedium)
                .foregroundStyle(DesignTokens.cocoa)
            Text(row.detail)
                .font(TypeScale.provenance)
                .foregroundStyle(DesignTokens.cocoaSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: DesignTokens.hero, alignment: .leading)
        .padding(.vertical, DesignTokens.Spacing.small)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }
}
