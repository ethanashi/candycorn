import SwiftUI

enum AppIcon: String, Sendable {
    case back = "chevron.left"
    case calendar = "calendar"
    case camera = "camera"
    case capture = "plus.circle.fill"
    case check = "checkmark"
    case checkCircle = "checkmark.circle"
    case chevronDown = "chevron.down"
    case chevronRight = "chevron.right"
    case clock = "clock"
    case close = "xmark"
    case download = "square.and.arrow.down"
    case history = "clock.arrow.circlepath"
    case home = "house"
    case journal = "square.and.pencil"
    case listPlus = "text.badge.plus"
    case microphone = "mic"
    case pause = "pause.fill"
    case pencil = "pencil"
    case play = "play.fill"
    case prepare = "calendar.badge.clock"
    case search = "magnifyingglass"
    case settings = "gearshape"
    case shield = "lock.shield"
    case sparkles = "sparkles"
    case stop = "stop.fill"
    case trash = "trash"
    case volume = "speaker.wave.2"

    var image: Image { Image(systemName: rawValue) }
}
