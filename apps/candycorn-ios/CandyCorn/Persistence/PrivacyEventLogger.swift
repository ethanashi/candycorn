import Foundation
import os

struct PrivacyEventLogger: EventLogging, AIEventLogging {
    private let logger = Logger(subsystem: "dev.candycorn.app", category: "events")

    func record(_ name: EventName, metrics: EventMetrics) {
        let duration = metrics.durationMilliseconds ?? -1
        let count = metrics.count ?? -1
        logger.info("event=\(name.rawValue, privacy: .public) duration_ms=\(duration, privacy: .public) count=\(count, privacy: .public)")
    }

    func record(_ name: AIEventName, metrics: AIEventMetrics) {
        let prompt = metrics.promptTokens ?? -1
        let completion = metrics.completionTokens ?? -1
        let reasoning = metrics.reasoningTokens ?? -1
        let total = metrics.totalTokens ?? -1
        let cost = metrics.costCredits ?? -1
        logger.info("ai_event=\(name.rawValue, privacy: .public) duration_ms=\(metrics.durationMilliseconds, privacy: .public) attempts=\(metrics.attemptCount, privacy: .public) prompt_tokens=\(prompt, privacy: .public) completion_tokens=\(completion, privacy: .public) reasoning_tokens=\(reasoning, privacy: .public) total_tokens=\(total, privacy: .public) cost_credits=\(cost, privacy: .public) provider=\(metrics.providerID, privacy: .public) model=\(metrics.modelID, privacy: .public) success=\(metrics.success, privacy: .public)")
    }
}
