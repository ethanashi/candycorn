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

/// v2: one card of rows. Short states sit at the right; long ones drop under the title.
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
        V2GroupCard(title: "Right now") {
            ForEach(rows) { row in
                V2ListRow(
                    icon: icon(for: row),
                    title: row.title,
                    detail: row.detail.count > 26 ? row.detail : nil,
                    value: row.detail.count > 26 ? nil : row.detail,
                    trailing: .none
                )
                .accessibilityLabel(row.accessibilityLabel)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Processing status")
    }

    private func icon(for row: AIProcessingStatusRow) -> AppIcon {
        switch row.id {
        case "journal": .sparkles
        case "voice": .waveform
        case "photo": .camera
        default: .cloudUpload
        }
    }
}
