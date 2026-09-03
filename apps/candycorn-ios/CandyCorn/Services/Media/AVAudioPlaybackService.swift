import Foundation

actor AVAudioPlaybackService: AudioPlaybackService {
    private let attachments: any AttachmentStore
    private let audioSession: any MediaAudioSessionClient
    private let playerFactory: any MediaPlaybackFactory
    private let files: any MediaFileClient
    private let clock: any MediaClock
    private let eventStream: AsyncStream<RecordingSnapshot>
    private let eventContinuation: AsyncStream<RecordingSnapshot>.Continuation
    private var player: (any MediaPlaybackClient)?
    private var updateTask: Task<Void, Never>?

    init(
        attachments: any AttachmentStore,
        audioSession: any MediaAudioSessionClient = SystemAudioSessionClient.shared,
        playerFactory: any MediaPlaybackFactory = SystemPlaybackFactory(),
        files: any MediaFileClient = SystemMediaFileClient(),
        clock: any MediaClock = SystemMediaClock()
    ) {
        self.attachments = attachments
        self.audioSession = audioSession
        self.playerFactory = playerFactory
        self.files = files
        self.clock = clock
        let pair = AsyncStream.makeStream(of: RecordingSnapshot.self, bufferingPolicy: .bufferingNewest(16))
        eventStream = pair.stream
        eventContinuation = pair.continuation
    }

    deinit {
        updateTask?.cancel()
        eventContinuation.finish()
    }

    func play(attachment: Attachment) async throws {
        guard attachment.kind == .audio, attachment.byteCount > 0 else { throw UserFacingError.playback }
        await stop()
        do {
            let url = try await attachments.url(for: attachment)
            guard try await files.fileSize(at: url) > 0 else { throw UserFacingError.playback }
            try await audioSession.beginPlayback()
            let newPlayer = try await playerFactory.makePlayer(url: url)
            guard await newPlayer.play() else { throw UserFacingError.playback }
            player = newPlayer
            await emitSnapshot(for: newPlayer, isPlaying: true)
            startUpdateLoop()
        } catch {
            player = nil
            await audioSession.endPlayback()
            throw UserFacingError.playback
        }
    }

    func pause() async {
        guard let player else { return }
        updateTask?.cancel()
        updateTask = nil
        await player.pause()
        await emitSnapshot(for: player, isPlaying: false)
    }

    func stop() async {
        updateTask?.cancel()
        updateTask = nil
        guard let player else { return }
        await player.stop()
        self.player = nil
        eventContinuation.yield(RecordingSnapshot(elapsedMilliseconds: 0, normalizedLevel: 0, isRecording: false))
        await audioSession.endPlayback()
    }

    func events() -> AsyncStream<RecordingSnapshot> { eventStream }

    func samplePlayback() async {
        guard let player else { return }
        let isPlaying = await player.isPlaying()
        await emitSnapshot(for: player, isPlaying: isPlaying)
        guard !isPlaying else { return }
        self.player = nil
        updateTask?.cancel()
        updateTask = nil
        await audioSession.endPlayback()
    }

    private func emitSnapshot(for player: any MediaPlaybackClient, isPlaying: Bool) async {
        let elapsed = await player.currentMilliseconds()
        let duration = await player.durationMilliseconds()
        let progress = duration > 0 ? min(max(Float(elapsed) / Float(duration), 0), 1) : 0
        eventContinuation.yield(RecordingSnapshot(
            elapsedMilliseconds: max(0, elapsed), normalizedLevel: progress, isRecording: isPlaying
        ))
    }

    private func startUpdateLoop() {
        updateTask?.cancel()
        updateTask = Task { [weak self] in
            for _ in 0..<Int.max {
                guard !Task.isCancelled, let self else { return }
                do {
                    try await self.clock.sleep(milliseconds: 250)
                } catch {
                    return
                }
                await self.samplePlayback()
                guard await self.player != nil else { return }
            }
        }
    }
}
