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

    @Test("Journal groups entries by day, newest first, with that day's latest mood")
    func journalGrouping() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_788_700_000)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let provenance = Provenance(voice: .user, label: "You said this", detail: "Test", occurredAt: now, sourceRoute: .journalDetail)
        func entry(_ id: UUID, _ date: Date) -> JournalEntry {
            JournalEntry(
                id: id, createdAt: date, updatedAt: date, inputType: .text, title: "Entry", rawText: "Words",
                cleanedText: nil, summaryItems: [], originalAttachmentID: nil, audioAttachmentID: nil, moodLogID: nil,
                pinnedForNextAppointment: false, processingStatus: .unprocessed, provenance: provenance
            )
        }
        let older = entry(UUID(), yesterday)
        let newer = entry(UUID(), now)
        let mood = MoodLog(id: UUID(), createdAt: now, mood: 6, anxiety: 7, energy: 4, customValues: [:], note: nil)
        let groups = JournalDayGroup.build(journals: [older, newer], moods: [mood], now: now, calendar: calendar)
        #expect(groups.count == 2)
        #expect(groups.first?.entries.first?.id == newer.id)
        #expect(groups.first?.mood?.mood == 6)
        #expect(groups.last?.mood == nil)
        #expect(groups.first?.title.hasPrefix("Today") == true)
        #expect(groups.last?.title.hasPrefix("Yesterday") == true)
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
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let metadataHasAlpha = properties[kCGImagePropertyHasAlpha] as? Bool
        #expect(
            Self.isOpaque(metadataHasAlpha: metadataHasAlpha, alphaInfo: image.alphaInfo),
            "App icon must decode without an alpha channel"
        )
    }

    @Test("Icon opacity accepts absent metadata and rejects alpha channels")
    func iconOpacityClassification() {
        #expect(Self.isOpaque(metadataHasAlpha: nil, alphaInfo: .none))
        #expect(Self.isOpaque(metadataHasAlpha: false, alphaInfo: .noneSkipFirst))
        #expect(Self.isOpaque(metadataHasAlpha: false, alphaInfo: .noneSkipLast))
        #expect(!Self.isOpaque(metadataHasAlpha: true, alphaInfo: .none))
        #expect(!Self.isOpaque(metadataHasAlpha: nil, alphaInfo: .premultipliedLast))
        #expect(!Self.isOpaque(metadataHasAlpha: false, alphaInfo: .last))
    }

    @Test("Logging calls contain event names and scalar metrics only")
    func privacySafeLogging() throws {
        let testsURL = URL(fileURLWithPath: #filePath)
        let sourceRoot = testsURL.deletingLastPathComponent().deletingLastPathComponent().appending(path: "CandyCorn")
        let enumerator = FileManager.default.enumerator(at: sourceRoot, includingPropertiesForKeys: nil)
        let urls = (enumerator?.allObjects as? [URL] ?? []).prefix(1_000)
        let contentFields = [
            "rawText", "cleanedText", "transcript", "manualNotes", "talkingPoint",
            "source.title", "payload", "relativePath", "fileURL", "promptText", "completionText",
            "requestBody", "responseBody", "localizedDescription",
        ]
        var offenders: [String] = []
        for url in urls where url.pathExtension == "swift" {
            let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false)
            for index in lines.indices where lines[index].contains("logger.record(") || lines[index].contains("logger.info(") {
                let call = Self.loggingCall(startingAt: index, lines: lines)
                if contentFields.contains(where: { call.contains($0) }) {
                    offenders.append("\(url.lastPathComponent):\(index + 1)")
                }
            }
        }
        #expect(offenders.isEmpty, "Content-bearing logging calls: \(offenders)")
    }

    private static func loggingCall(startingAt index: Int, lines: [Substring]) -> String {
        var result = ""
        var depth = 0
        let end = min(lines.count, index + 40)
        for position in index..<end {
            let line = String(lines[position])
            result += line
            depth += line.reduce(into: 0) { count, character in
                if character == "(" { count += 1 }
                if character == ")" { count -= 1 }
            }
            if depth <= 0 { break }
        }
        return result
    }

    private static func isOpaque(metadataHasAlpha: Bool?, alphaInfo: CGImageAlphaInfo) -> Bool {
        let hasOpaqueDecoderFormat = switch alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            true
        default:
            false
        }
        return metadataHasAlpha != true && hasOpaqueDecoderFormat
    }
}
