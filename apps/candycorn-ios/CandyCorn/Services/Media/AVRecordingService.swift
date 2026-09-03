import AVFoundation
import Foundation

actor AVRecordingService: RecordingService {
    private struct ActiveRecording: Sendable {
        let id: UUID
        let kind: RecordingKind
        let url: URL
        let recorder: any MediaRecorderClient
        let startedAtMilliseconds: Int64
        var nextCheckpointMilliseconds: Int
    }

    private struct FinalizedSource: Sendable {
        let recording: LocalRecording
        let checkpointFailed: Bool
    }

    private enum State: Sendable {
        case idle
        case active(ActiveRecording)
        case finalizing(Task<FinalizedSource, Error>)
        case registering(FinalizedSource, Task<Void, Error>)
        case pendingRegistration(FinalizedSource)
        case stopped(LocalRecording)
    }

    private let attachments: any AttachmentStore
    private let registration: any AttachmentRegistrationSink
    private let logger: any EventLogging
    private let permission: any MediaPermissionClient
    private let audioSession: any MediaAudioSessionClient
    private let recorderFactory: any MediaRecorderFactory
    private let checkpoint: any RecordingCheckpointSink
    private let files: any MediaFileClient
    private let clock: any MediaClock
    private let eventStream: AsyncStream<RecordingEvent>
    private let eventContinuation: AsyncStream<RecordingEvent>.Continuation
    private var state: State = .idle
    private var meterTask: Task<Void, Never>?
    private var systemEventTask: Task<Void, Never>?

    init(
        attachments: any AttachmentStore,
        registration: any AttachmentRegistrationSink,
        logger: any EventLogging,
        permission: any MediaPermissionClient = MicrophonePermissionClient(),
        audioSession: any MediaAudioSessionClient = SystemAudioSessionClient.shared,
        recorderFactory: any MediaRecorderFactory = SystemRecorderFactory(),
        checkpoint: any RecordingCheckpointSink,
        files: any MediaFileClient = SystemMediaFileClient(),
        clock: any MediaClock = SystemMediaClock()
    ) {
        self.attachments = attachments
        self.registration = registration
        self.logger = logger
        self.permission = permission
        self.audioSession = audioSession
        self.recorderFactory = recorderFactory
        self.checkpoint = checkpoint
        self.files = files
        self.clock = clock
        let pair = AsyncStream.makeStream(of: RecordingEvent.self, bufferingPolicy: .bufferingNewest(32))
        eventStream = pair.stream
        eventContinuation = pair.continuation
    }

    deinit {
        meterTask?.cancel()
        systemEventTask?.cancel()
        eventContinuation.finish()
    }

    func authorizationStatus() async -> CaptureAuthorization {
        await permission.authorizationStatus()
    }

    func requestPermission() async -> Bool {
        await permission.requestPermission()
    }

    func start(kind: RecordingKind) async throws {
        guard await permission.authorizationStatus() == .authorized else { throw UserFacingError.recording }
        switch state {
        case .idle, .stopped:
            break
        case .active, .finalizing, .registering, .pendingRegistration:
            throw UserFacingError.recording
        }

        try await audioSession.beginRecording()
        do {
            let url = try await attachments.allocateURL(kind: .audio, fileExtension: "m4a")
            let recorder = try await recorderFactory.makeRecorder(url: url, settings: Self.recordingSettings)
            guard await recorder.start() else { throw UserFacingError.recording }
            let active = ActiveRecording(
                id: UUID(), kind: kind, url: url, recorder: recorder,
                startedAtMilliseconds: clock.monotonicMilliseconds(), nextCheckpointMilliseconds: 15_000
            )
            state = .active(active)
            eventContinuation.yield(.snapshot(RecordingSnapshot(elapsedMilliseconds: 0, normalizedLevel: 0, isRecording: true)))
            logger.record(.recordingStarted, metrics: EventMetrics())
            startMeterLoop()
            startSystemEventLoopIfNeeded()
        } catch {
            await audioSession.endRecording()
            throw UserFacingError.recording
        }
    }

    func stop(reason: RecordingStopReason) async throws -> LocalRecording {
        switch state {
        case let .stopped(recording):
            return recording
        case let .active(active):
            return try await beginFinalization(active: active, reason: reason)
        case let .finalizing(task):
            return try await completeFinalization(task)
        case let .registering(source, task):
            return try await completeRegistration(source: source, task: task)
        case let .pendingRegistration(source):
            return try await beginRegistration(source)
        case .idle:
            throw UserFacingError.recording
        }
    }

    func events() -> AsyncStream<RecordingEvent> { eventStream }

    static func normalizedPower(decibels: Float) -> Float {
        guard decibels.isFinite else { return 0 }
        let clamped = min(max(decibels, -60), 0)
        return min(max((clamped + 60) / 60, 0), 1)
    }

    func sampleMeter() async {
        guard case var .active(active) = state else { return }
        await active.recorder.updateMeters()
        let power = await active.recorder.averagePower()
        let recorderDuration = await active.recorder.durationMilliseconds()
        guard case let .active(current) = state, current.id == active.id else { return }
        let monotonicDuration = max(0, Int(clock.monotonicMilliseconds() - active.startedAtMilliseconds))
        let elapsed = max(monotonicDuration, recorderDuration)
        eventContinuation.yield(.snapshot(RecordingSnapshot(
            elapsedMilliseconds: elapsed,
            normalizedLevel: Self.normalizedPower(decibels: power),
            isRecording: true
        )))
        guard case let .appointment(appointmentID) = active.kind,
              elapsed >= active.nextCheckpointMilliseconds else { return }
        active.nextCheckpointMilliseconds += 15_000
        state = .active(active)
        do {
            try await checkpoint.write(appointmentID: appointmentID, durationMilliseconds: elapsed)
        } catch {
            eventContinuation.yield(.failed(message: "Recording is continuing, but its latest duration could not be saved."))
        }
    }

    func handleSystemEvent(_ event: MediaSystemEvent) async {
        guard case .active = state else { return }
        switch event {
        case .interruptionBegan:
            await stopAfterSystemChange()
        case .routeChanged:
            guard !(await audioSession.hasInputRoute()) else { return }
            await stopAfterSystemChange()
        }
    }

    private func beginFinalization(active: ActiveRecording, reason: RecordingStopReason) async throws -> LocalRecording {
        meterTask?.cancel()
        meterTask = nil
        let task = Task { [files, checkpoint, clock] in
            let recorderDuration = await active.recorder.durationMilliseconds()
            await active.recorder.stop()
            let byteCount = try await files.synchronizeAndFileSize(at: active.url)
            try await files.applyFileProtection(at: active.url)
            let elapsed = max(recorderDuration, max(0, Int(clock.monotonicMilliseconds() - active.startedAtMilliseconds)))
            var checkpointFailed = false
            if case let .appointment(appointmentID) = active.kind {
                do {
                    try await checkpoint.write(appointmentID: appointmentID, durationMilliseconds: elapsed)
                } catch {
                    checkpointFailed = true
                }
            }
            let attachment = Attachment(
                id: UUID(), kind: .audio,
                relativePath: try MediaPath.relativePath(kind: .audio, url: active.url),
                mediaType: "audio/mp4", byteCount: byteCount,
                durationMilliseconds: elapsed, createdAt: clock.wallNow(), isSample: false
            )
            return FinalizedSource(
                recording: LocalRecording(attachment: attachment, fileURL: active.url, stopReason: reason),
                checkpointFailed: checkpointFailed
            )
        }
        state = .finalizing(task)
        return try await completeFinalization(task)
    }

    private func completeFinalization(_ task: Task<FinalizedSource, Error>) async throws -> LocalRecording {
        let source: FinalizedSource
        do {
            source = try await task.value
        } catch {
            state = .idle
            await audioSession.endRecording()
            eventContinuation.yield(.failed(message: UserFacingError.recording.message))
            throw UserFacingError.recording
        }
        switch state {
        case let .stopped(recording):
            return recording
        case let .registering(existing, registrationTask):
            return try await completeRegistration(source: existing, task: registrationTask)
        case let .pendingRegistration(existing):
            return try await beginRegistration(existing)
        case .finalizing:
            state = .pendingRegistration(source)
            await audioSession.endRecording()
            return try await beginRegistration(source)
        case .idle, .active:
            throw UserFacingError.recording
        }
    }

    private func beginRegistration(_ source: FinalizedSource) async throws -> LocalRecording {
        let task = Task { [registration] in
            try await registration.register(source.recording.attachment)
        }
        state = .registering(source, task)
        return try await completeRegistration(source: source, task: task)
    }

    private func completeRegistration(source: FinalizedSource, task: Task<Void, Error>) async throws -> LocalRecording {
        do {
            try await task.value
            if case let .stopped(recording) = state { return recording }
            state = .stopped(source.recording)
            if source.checkpointFailed {
                eventContinuation.yield(.failed(message: "The recording was saved, but its latest duration could not be updated."))
            }
            eventContinuation.yield(.stopped(source.recording))
            logger.record(.recordingStopped, metrics: EventMetrics(durationMilliseconds: source.recording.attachment.durationMilliseconds))
            logger.record(.attachmentSaved, metrics: EventMetrics(count: 1))
            return source.recording
        } catch {
            state = .pendingRegistration(source)
            eventContinuation.yield(.failed(message: "The recording was saved, but its details could not be updated."))
            throw UserFacingError.saving
        }
    }

    private func startMeterLoop() {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            for _ in 0..<Int.max {
                guard !Task.isCancelled, let self else { return }
                do {
                    try await self.clock.sleep(milliseconds: 100)
                } catch {
                    return
                }
                await self.sampleMeter()
            }
        }
    }

    private func startSystemEventLoopIfNeeded() {
        guard systemEventTask == nil else { return }
        systemEventTask = Task { [weak self, audioSession] in
            let stream = await audioSession.events()
            var remaining = Int.max
            for await event in stream {
                guard remaining > 0, !Task.isCancelled, let self else { return }
                remaining -= 1
                await self.handleSystemEvent(event)
            }
        }
    }

    private func stopAfterSystemChange() async {
        do {
            _ = try await stop(reason: .interruption)
        } catch {
            eventContinuation.yield(.failed(message: UserFacingError.recording.message))
        }
    }

    private static let recordingSettings: [String: Sendable] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 44_100.0,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
    ]
}
