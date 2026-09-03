import Foundation

enum ScreenshotScenario: String, CaseIterable, Sendable {
    static let photoJournalID = UUID(uuid: (0x81, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01))
    static let photoAttachmentID = UUID(uuid: (0x82, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01))
    case openRouterKey = "openrouter-key"
    case journalSend = "journal-send"
    case photoSend = "photo-send"
    case sessionSend = "session-send"
    case prepareSend = "prepare-send"

    static func parse(arguments: [String]) -> ScreenshotScenario? {
        guard let flag = arguments.firstIndex(of: "-sheet") else { return nil }
        let valueIndex = arguments.index(after: flag)
        guard valueIndex < arguments.endIndex else { return nil }
        return ScreenshotScenario(rawValue: arguments[valueIndex])
    }

    var sendAction: AISendAction? {
        switch self {
        case .openRouterKey:
            nil
        case .journalSend:
            .rewriteJournal(SeededData.footballJournalID)
        case .photoSend:
            .readPhoto(
                journalID: Self.photoJournalID,
                attachmentID: Self.photoAttachmentID
            )
        case .sessionSend:
            .summarizeSession(SeededData.therapySessionID)
        case .prepareSend:
            .generateAppointmentBrief(.therapy)
        }
    }
}
