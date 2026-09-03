import Foundation
import Testing
@testable import CandyCorn

@Suite("Native audio playback adapter")
struct AudioPlaybackServiceTests {
    @Test("Playback reports progress and supports pause and stop")
    func lifecycle() async throws {
        let session = TestAudioSession()
        let player = TestPlaybackPlayer(current: 1_250, duration: 5_000)
        let service = AVAudioPlaybackService(
            attachments: TestAttachmentStore(), audioSession: session,
            playerFactory: TestPlaybackFactory(player: player),
            files: TestMediaFiles(defaultSize: 1_024), clock: FixedMediaClock()
        )
        let stream = await service.events()
        var iterator = stream.makeAsyncIterator()
        try await service.play(attachment: Self.audioAttachment)
        #expect(await iterator.next() == RecordingSnapshot(elapsedMilliseconds: 1_250, normalizedLevel: 0.25, isRecording: true))
        await service.pause()
        #expect(await iterator.next() == RecordingSnapshot(elapsedMilliseconds: 1_250, normalizedLevel: 0.25, isRecording: false))
        #expect(await player.pauseCount == 1)
        await service.stop()
        #expect(await iterator.next() == RecordingSnapshot(elapsedMilliseconds: 0, normalizedLevel: 0, isRecording: false))
        #expect(await player.stopCount == 1)
        #expect(await session.endPlaybackCount == 1)
    }

    @Test("Missing audio and an active recording fail safely")
    func unavailablePlayback() async {
        let missing = AVAudioPlaybackService(
            attachments: TestAttachmentStore(), audioSession: TestAudioSession(),
            playerFactory: TestPlaybackFactory(player: TestPlaybackPlayer()),
            files: TestMediaFiles(defaultSize: 0), clock: FixedMediaClock()
        )
        await #expect(throws: UserFacingError.playback) {
            try await missing.play(attachment: Self.audioAttachment)
        }

        let busySession = TestAudioSession()
        await busySession.setRejectPlayback(true)
        let busy = AVAudioPlaybackService(
            attachments: TestAttachmentStore(), audioSession: busySession,
            playerFactory: TestPlaybackFactory(player: TestPlaybackPlayer()),
            files: TestMediaFiles(defaultSize: 1), clock: FixedMediaClock()
        )
        await #expect(throws: UserFacingError.playback) {
            try await busy.play(attachment: Self.audioAttachment)
        }
        #expect(await busySession.beginPlaybackCount == 0)
    }

    @Test("Timestamp playback seeks before play and rejects invalid offsets")
    func timestampSeeking() async throws {
        let player = TestPlaybackPlayer(duration: 5_000)
        let service = AVAudioPlaybackService(
            attachments: TestAttachmentStore(), audioSession: TestAudioSession(),
            playerFactory: TestPlaybackFactory(player: player),
            files: TestMediaFiles(defaultSize: 1_024), clock: FixedMediaClock()
        )

        try await service.play(attachment: Self.audioAttachment, fromMilliseconds: 2_400)
        #expect(await player.seekValues == [2_400])
        #expect(await player.playCount == 1)
        await service.stop()

        await #expect(throws: UserFacingError.playback) {
            try await service.play(attachment: Self.audioAttachment, fromMilliseconds: -1)
        }
        await #expect(throws: UserFacingError.playback) {
            try await service.play(attachment: Self.audioAttachment, fromMilliseconds: 5_001)
        }
        #expect(await player.playCount == 1)
    }

    private static let audioAttachment = CandyCorn.Attachment(
        id: UUID(uuidString: "A0000000-0000-0000-0000-000000000002")!, kind: .audio,
        relativePath: "audio/source.m4a", mediaType: "audio/mp4", byteCount: 1_024,
        durationMilliseconds: 5_000, createdAt: Date(timeIntervalSince1970: 1), isSample: false
    )
}

actor TestPlaybackPlayer: MediaPlaybackClient {
    private var current: Int
    private let duration: Int
    private var playing = false
    private(set) var pauseCount = 0
    private(set) var stopCount = 0
    private(set) var playCount = 0
    private(set) var seekValues: [Int] = []

    init(current: Int = 0, duration: Int = 1_000) {
        self.current = current
        self.duration = duration
    }

    func play() -> Bool { playing = true; playCount += 1; return true }
    func seek(toMilliseconds milliseconds: Int) -> Bool {
        guard milliseconds >= 0, milliseconds <= duration else { return false }
        current = milliseconds
        seekValues.append(milliseconds)
        return true
    }
    func pause() { playing = false; pauseCount += 1 }
    func stop() { playing = false; stopCount += 1 }
    func currentMilliseconds() -> Int { current }
    func durationMilliseconds() -> Int { duration }
    func isPlaying() -> Bool { playing }
}

struct TestPlaybackFactory: MediaPlaybackFactory {
    let player: TestPlaybackPlayer
    func makePlayer(url: URL) -> any MediaPlaybackClient {
        _ = url
        return player
    }
}
