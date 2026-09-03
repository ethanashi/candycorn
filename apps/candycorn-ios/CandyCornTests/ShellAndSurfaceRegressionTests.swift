import Foundation
import ImageIO
import Testing
@testable import CandyCorn

@Suite("Shell regressions")
struct ShellAndSurfaceRegressionTests {
    @Test("Mood positions use ten equal regions and clamp")
    func moodPositionMapping() {
        #expect(MoodBandSelection.value(at: -1, width: 100) == 1)
        #expect(MoodBandSelection.value(at: 0, width: 100) == 1)
        #expect(MoodBandSelection.value(at: 9.9, width: 100) == 1)
        #expect(MoodBandSelection.value(at: 10, width: 100) == 2)
        #expect(MoodBandSelection.value(at: 75, width: 100) == 8)
        #expect(MoodBandSelection.value(at: 100, width: 100) == 10)
        #expect(MoodBandSelection.value(at: 130, width: 100) == 10)
        #expect(MoodBandSelection.adjusted(1, by: -1) == 1)
        #expect(MoodBandSelection.adjusted(10, by: 1) == 10)
    }

    @Test("Today orders appointment, three open points, then current goal")
    func todayOrder() {
        let open = SeededData.talkingPoints[0]
        var points = Array(repeating: open, count: 4)
        for index in points.indices {
            points[index] = TalkingPoint(
                id: UUID(), text: points[index].text, source: points[index].source,
                sourceID: points[index].sourceID, targetAppointmentKind: .therapy,
                isImportant: false, status: .open, createdAt: points[index].createdAt,
                provenance: points[index].provenance
            )
        }
        let goal = SeededData.goals[0]
        let sections = TodayOrderingModel.sections(talkingPoints: points, currentGoal: goal)
        #expect(sections.count == 5)
        #expect(sections.first == .appointment)
        #expect(sections.last == .currentGoal(goal.id))
    }

    @Test("Product-facing strings contain no implementation copy")
    func productCopy() throws {
        let testsURL = URL(fileURLWithPath: #filePath)
        let sourceRoot = testsURL.deletingLastPathComponent().deletingLastPathComponent().appending(path: "CandyCorn")
        let forbidden = ["this shell", "in-memory", "not active in this phase", "prototype", "simulated"]
        let enumerator = FileManager.default.enumerator(at: sourceRoot, includingPropertiesForKeys: nil)
        let urls = (enumerator?.allObjects as? [URL] ?? []).prefix(1_000)
        var offenders: [String] = []
        for url in urls {
            guard url.pathExtension == "swift" else { continue }
            let source = try String(contentsOf: url, encoding: .utf8).lowercased()
            for phrase in forbidden where source.contains("\"\(phrase)") || source.contains("\(phrase)\"") {
                offenders.append("\(url.lastPathComponent): \(phrase)")
            }
        }
        #expect(offenders.isEmpty, "Forbidden product copy: \(offenders)")
    }

    @Test("App icon is an opaque 1024 point PNG")
    func appIcon() throws {
        let testsURL = URL(fileURLWithPath: #filePath)
        let iconURL = testsURL.deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "CandyCorn/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png")
        let source = try #require(CGImageSourceCreateWithURL(iconURL as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 1024)
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == 1024)
        #expect(properties[kCGImagePropertyHasAlpha] as? Bool == false)
    }

    @Test("Logging calls contain event names and scalar metrics only")
    func privacySafeLogging() throws {
        let testsURL = URL(fileURLWithPath: #filePath)
        let sourceRoot = testsURL.deletingLastPathComponent().deletingLastPathComponent().appending(path: "CandyCorn")
        let enumerator = FileManager.default.enumerator(at: sourceRoot, includingPropertiesForKeys: nil)
        let urls = (enumerator?.allObjects as? [URL] ?? []).prefix(1_000)
        let contentFields = [
            "rawText", "cleanedText", "transcript", "manualNotes", "talkingPoint",
            "title", "payload", "relativePath", "fileURL",
        ]
        var offenders: [String] = []
        for url in urls where url.pathExtension == "swift" {
            let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false)
            for (index, line) in lines.enumerated() where line.contains("logger.record(") {
                let value = String(line)
                if value.contains("\\(") || contentFields.contains(where: { value.contains($0) }) {
                    offenders.append("\(url.lastPathComponent):\(index + 1)")
                }
            }
        }
        #expect(offenders.isEmpty, "Content-bearing logging calls: \(offenders)")
    }
}
