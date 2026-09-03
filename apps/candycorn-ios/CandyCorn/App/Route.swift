import Foundation

enum RoutePresentation: Sendable, Equatable {
    case root
    case pushed
    case fullScreen
}

enum Route: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case welcome = "/welcome"
    case today = "/today"
    case checkIn = "/check-in"
    case capture = "/capture"
    case journalVoice = "/journal/voice"
    case journalWrite = "/journal/write"
    case journalPhoto = "/journal/photo"
    case journalDetail = "/journal/entry/football-and-guilt"
    case journalSuggestions = "/journal/suggestions"
    case goals = "/goals"
    case bringUp = "/bring-up"
    case appointments = "/appointments"
    case recordAppointment = "/appointments/record"
    case activeAppointment = "/appointments/active"
    case therapySession = "/sessions/therapy-sep-2"
    case tmsPre = "/tms/pre-session"
    case tmsPost = "/tms/post-session"
    case prepareTherapy = "/prepare/therapy"
    case prepareTMS = "/prepare/tms"
    case history = "/history"
    case search = "/search"
    case settingsPrivacy = "/settings/privacy"
    case settingsAI = "/settings/ai"
    case settingsData = "/settings/data"

    var id: Self { self }
    var order: Int { Self.allCases.firstIndex(of: self).map { $0 + 1 } ?? 0 }

    var screenshotFilename: String {
        let names = [
            "welcome", "today", "check-in", "capture", "voice-rant", "text-journal",
            "journal-photo", "journal-detail", "ai-suggestions", "goals", "bring-up",
            "appointments", "record-appointment", "active-appointment", "therapy-session",
            "tms-pre", "tms-post", "prepare-therapy", "prepare-tms", "history", "search",
            "settings-privacy", "settings-ai", "settings-data",
        ]
        guard order > 0, order <= names.count else { return "unknown.png" }
        return String(format: "%02d-%@.png", order, names[order - 1])
    }

    var tab: AppTab? {
        switch self {
        case .welcome: nil
        case .today, .checkIn, .goals, .bringUp, .appointments: .today
        case .capture, .journalVoice, .journalWrite, .journalPhoto, .journalDetail, .journalSuggestions: .journal
        case .recordAppointment, .activeAppointment: nil
        case .therapySession, .tmsPost, .history, .search: .history
        case .tmsPre, .prepareTherapy, .prepareTMS: .prepare
        case .settingsPrivacy, .settingsAI, .settingsData: .settings
        }
    }

    var presentation: RoutePresentation {
        switch self {
        case .welcome, .today, .prepareTherapy, .history,
             .settingsPrivacy, .settingsAI, .settingsData:
            .root
        case .checkIn, .capture, .journalVoice, .journalWrite, .journalPhoto,
             .recordAppointment, .activeAppointment:
            .fullScreen
        default:
            .pushed
        }
    }

    var isPresentedFlow: Bool { presentation == .fullScreen }

    var showsFloatingTabBar: Bool {
        switch self {
        case .today, .journalDetail, .journalSuggestions, .goals, .bringUp, .appointments,
             .therapySession, .prepareTherapy, .prepareTMS, .history, .search,
             .settingsPrivacy, .settingsAI, .settingsData:
            true
        default:
            false
        }
    }

    static func parseLaunchArguments(_ arguments: [String]) -> Route? {
        guard let flag = arguments.firstIndex(of: "-screen") else { return nil }
        let valueIndex = arguments.index(after: flag)
        guard valueIndex < arguments.endIndex else { return nil }
        return Route(rawValue: arguments[valueIndex])
    }
}
