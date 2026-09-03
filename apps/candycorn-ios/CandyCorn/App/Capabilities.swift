import Foundation

struct LocalRecording: Equatable, Sendable {
    let id: UUID
    let durationMilliseconds: Int
    let localURL: URL
}

enum RecordingKind: Sendable {
    case journal
    case appointment
}

protocol RecordingPort: Sendable {
    func start(kind: RecordingKind) async throws
    func finish() async throws -> LocalRecording
    func cancel() async throws
}

protocol PhotoCapturePort: Sendable {
    func captureJournalPage() async throws -> URL
}

protocol ProcessingPort: Sendable {
    func transcribe(_ recording: LocalRecording) async throws -> [TranscriptSegment]
    func organizeJournal(_ entry: JournalEntry) async throws -> JournalEntry
}

protocol ExportPort: Sendable {
    func exportArchive() async throws -> URL
}
