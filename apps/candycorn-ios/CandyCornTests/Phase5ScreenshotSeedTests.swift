import Foundation
import Testing
@testable import CandyCorn

@Suite("Phase 5 screenshot seed")
struct Phase5ScreenshotSeedTests {
    private static let now = Date(timeIntervalSince1970: 1_788_654_600)

    @Test("Seeded snapshot carries a readable weekly summary and a pending progress suggestion")
    func seedProducesBothArtifacts() throws {
        let base = SeededData.careSnapshot
        let preparation = try WeeklyConsolidator.makePreparation(snapshot: base, for: Self.now, calendar: .autoupdatingCurrent)
        let sources = preparation?.input.sources ?? []
        let kinds = sources.map { "\($0.document.kind.rawValue):\($0.provenance)" }
        #expect(preparation != nil, "preparation nil")
        #expect(!sources.isEmpty, "no sources; kinds=\(kinds)")

        let seeded = Phase5ScreenshotSeed.applyingIfNeeded(to: base, arguments: ["CandyCorn", "-screen", "/history"], now: Self.now)
        let weekly = seeded.artifacts.filter { $0.kind == .weeklySummary }
        #expect(weekly.count == 1, "weekly artifacts=\(weekly.count) sources=\(kinds)")
        #expect(WeeklyConsolidator.currentSummary(in: seeded.artifacts, for: Self.now) != nil)
        #expect(seeded.artifacts.contains { $0.kind == .goalProgressSuggestions })

        let untouched = Phase5ScreenshotSeed.applyingIfNeeded(to: base, arguments: ["CandyCorn"], now: Self.now)
        #expect(untouched.artifacts.count == base.artifacts.count)
    }
}
