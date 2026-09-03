import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable, Sendable {
    case privacy = "Privacy"
    case ai = "AI"
    case data = "Data"

    var id: Self { self }

    var route: Route {
        switch self {
        case .privacy: .settingsPrivacy
        case .ai: .settingsAI
        case .data: .settingsData
        }
    }
}
