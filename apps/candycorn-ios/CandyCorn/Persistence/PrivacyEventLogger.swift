import Foundation
import os

struct PrivacyEventLogger: EventLogging {
    private let logger = Logger(subsystem: "dev.candycorn.app", category: "events")

    func record(_ name: EventName, metrics: EventMetrics) {
        let duration = metrics.durationMilliseconds ?? -1
        let count = metrics.count ?? -1
        logger.info("event=\(name.rawValue, privacy: .public) duration_ms=\(duration, privacy: .public) count=\(count, privacy: .public)")
    }
}
