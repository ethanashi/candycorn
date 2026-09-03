import Foundation
import Testing
@testable import CandyCorn

@Suite("Native recording adapter")
struct RecordingServiceTests {
    @Test("Permission is requested only on demand")
    func permissionTiming() async {
        let permission = TestMediaPermission(status: .notDetermined, requestResult: true)
        let service = makeService(permission: permission)
        #expect(await permission.requestCount == 0)
        #expect(await service.authorizationStatus() == .notDetermined)
        #expect(await permission.requestCount == 0)
        #expect(await service.requestPermission())
        #expect(await permission.requestCount == 1)
    }

    @Test("Metering clamps levels and checkpoints appointments every fifteen seconds")
    func meteringAndCheckpoints() async throws {
        let recorder = TestMediaRecorder(power: -30, duration: 15_000)
        let checkpoint = TestCheckpoint(failuresRemaining: 1)
        let service = makeService(recorder: recorder, checkpoint: checkpoint)
        let stream = await service.events()
        var iterator = stream.makeAsyncIterator()
        try await service.start(kind: .appointment(id: TestValues.appointmentID))
        _ = await iterator.next()
        await service.sampleMeter()
        #expect(await iterator.next() == .snapshot(RecordingSnapshot(elapsedMilliseconds: 15_000, normalizedLevel: 0.5, isRecording: true)))
        #expect(await iterator.next() == .failed(message: "Recording is continuing, but its latest duration could not be saved."))
        await recorder.setDuration(30_000)
        await service.sampleMeter()
        #expect(await checkpoint.writes == [15_000, 30_000])
        #expect(AVRecordingService.normalizedPower(decibels: .nan) == 0)
        #expect(AVRecordingService.normalizedPower(decibels: -90) == 0)
        #expect(AVRecordingService.normalizedPower(decibels: 12) == 1)
    }

    @Test("Stop finalizes, registers, emits, and is idempotent")
    func stopOrderingAndIdempotence() async throws {
        let recorder = TestMediaRecorder(power: -10, duration: 2_400)
        let files = TestMediaFiles(defaultSize: 4_096)
        let registration = TestAttachmentRegistration()
        let session = TestAudioSession()
        let service = makeService(recorder: recorder, files: files, registration: registration, session: session)
        let stream = await service.events()
        var iterator = stream.makeAsyncIterator()
        try await service.start(kind: .journal)
        _ = await iterator.next()
        let first = try await service.stop(reason: .user)
        let stoppedEvent = await iterator.next()
        let second = try await service.stop(reason: .failure)
        #expect(first == second)
        #expect(first.stopReason == .user)
        #expect(first.attachment.byteCount == 4_096)
        #expect(await registration.attachments == [first.attachment])
        #expect(stoppedEvent == .stopped(first))
        #expect(await recorder.stopCount == 1)
        #expect(await files.protectedURLs == [TestValues.audioURL])
        #expect(await session.endRecordingCount == 1)
    }

    @Test("Interruption before a meter tick still saves")
    func interruptionSaves() async throws {
        let recorder = TestMediaRecorder(power: -60, duration: 320)
        let registration = TestAttachmentRegistration()
        let service = makeService(recorder: recorder, registration: registration)
        try await service.start(kind: .journal)
        await service.handleSystemEvent(.interruptionBegan)
        let saved = try #require(await registration.attachments.first)
        #expect(saved.durationMilliseconds == 320)
        #expect(await recorder.stopCount == 1)
    }

    @Test("A zero byte finalization is rejected without metadata")
    func zeroByteRejected() async {
        let registration = TestAttachmentRegistration()
        let service = makeService(files: TestMediaFiles(defaultSize: 0), registration: registration)
        do {
            try await service.start(kind: .journal)
            _ = try await service.stop(reason: .user)
            Issue.record("Expected zero-byte recording to fail")
        } catch {
            #expect(error as? UserFacingError == .recording)
        }
        #expect(await registration.attachments.isEmpty)
    }

    @Test("A metadata failure keeps the finalized source available for retry")
    func registrationRetry() async throws {
        let registration = TestAttachmentRegistration(failuresRemaining: 1)
        let recorder = TestMediaRecorder(power: -20, duration: 900)
        let service = makeService(recorder: recorder, registration: registration)
        try await service.start(kind: .journal)
        await #expect(throws: UserFacingError.saving) {
            _ = try await service.stop(reason: .user)
        }
        let recording = try await service.stop(reason: .user)
        #expect(recording.fileURL == TestValues.audioURL)
        #expect(await recorder.stopCount == 1)
        #expect(await registration.attachments == [recording.attachment])
    }

    private func makeService(
        permission: TestMediaPermission = TestMediaPermission(status: .authorized),
        recorder: TestMediaRecorder = TestMediaRecorder(power: -20, duration: 1_000),
        checkpoint: TestCheckpoint = TestCheckpoint(),
        files: TestMediaFiles = TestMediaFiles(defaultSize: 1_024),
        registration: TestAttachmentRegistration = TestAttachmentRegistration(),
        session: TestAudioSession = TestAudioSession()
    ) -> AVRecordingService {
        AVRecordingService(
            attachments: TestAttachmentStore(), registration: registration, logger: NoOpEventLogger(),
            permission: permission, audioSession: session, recorderFactory: TestRecorderFactory(recorder: recorder),
            checkpoint: checkpoint, files: files, clock: FixedMediaClock()
        )
    }
}

enum TestValues {
    static let audioURL = URL(fileURLWithPath: "/tmp/candycorn-media-tests/audio/source.m4a")
    static let imageURL = URL(fileURLWithPath: "/tmp/candycorn-media-tests/images/source.jpg")
    static let appointmentID = UUID(uuidString: "A0000000-0000-0000-0000-000000000001")!
}

actor TestMediaPermission: MediaPermissionClient {
    private var status: CaptureAuthorization
    private let requestResult: Bool
    private(set) var requestCount = 0

    init(status: CaptureAuthorization, requestResult: Bool? = nil) {
        self.status = status
        self.requestResult = requestResult ?? (status == .authorized)
    }

    func authorizationStatus() -> CaptureAuthorization { status }
    func requestPermission() -> Bool {
        requestCount += 1
        if requestResult { status = .authorized }
        return requestResult
    }
}

actor TestAudioSession: MediaAudioSessionClient {
    private(set) var beginRecordingCount = 0
    private(set) var endRecordingCount = 0
    private(set) var beginPlaybackCount = 0
    private(set) var endPlaybackCount = 0
    private var hasInput = true
    private var rejectPlayback = false
    private let stream: AsyncStream<MediaSystemEvent>
    private let continuation: AsyncStream<MediaSystemEvent>.Continuation

    init() {
        let pair = AsyncStream.makeStream(of: MediaSystemEvent.self, bufferingPolicy: .bufferingNewest(8))
        stream = pair.stream
        continuation = pair.continuation
    }

    func beginRecording() throws { beginRecordingCount += 1 }
    func endRecording() { endRecordingCount += 1 }
    func beginPlayback() throws {
        guard !rejectPlayback else { throw UserFacingError.playback }
        beginPlaybackCount += 1
    }
    func endPlayback() { endPlaybackCount += 1 }
    func hasInputRoute() -> Bool { hasInput }
    func events() -> AsyncStream<MediaSystemEvent> { stream }
    func send(_ event: MediaSystemEvent) { continuation.yield(event) }
    func setRejectPlayback(_ value: Bool) { rejectPlayback = value }
}

actor TestMediaRecorder: MediaRecorderClient {
    private var power: Float
    private var duration: Int
    private(set) var stopCount = 0
    private var starts = true

    init(power: Float, duration: Int) {
        self.power = power
        self.duration = duration
    }

    func start() -> Bool { starts }
    func stop() { stopCount += 1 }
    func updateMeters() {}
    func averagePower() -> Float { power }
    func durationMilliseconds() -> Int { duration }
    func setDuration(_ value: Int) { duration = value }
}

struct TestRecorderFactory: MediaRecorderFactory {
    let recorder: TestMediaRecorder
    func makeRecorder(url: URL, settings: [String: Sendable]) -> any MediaRecorderClient {
        _ = url
        _ = settings
        return recorder
    }
}

actor TestAttachmentStore: AttachmentStore {
    private var audioURL = TestValues.audioURL
    private var imageURL = TestValues.imageURL
    private var resolvedURL = TestValues.audioURL

    func allocateURL(kind: AttachmentKind, fileExtension: String) throws -> URL {
        guard !fileExtension.isEmpty else { throw UserFacingError.saving }
        return kind == .image ? imageURL : audioURL
    }
    func url(for attachment: CandyCorn.Attachment) -> URL {
        _ = attachment
        return resolvedURL
    }
    func copyIntoExport(_ attachment: CandyCorn.Attachment, destination: URL) {
        _ = attachment
        _ = destination
    }
    func removeAll() {}
}

actor TestMediaFiles: MediaFileClient {
    private let defaultSize: Int64
    private(set) var protectedURLs: [URL] = []
    private(set) var writes: [URL: Data] = [:]
    private var validJPEG = true

    init(defaultSize: Int64) { self.defaultSize = defaultSize }

    func synchronizeAndFileSize(at url: URL) throws -> Int64 {
        if let data = writes[url] { return Int64(data.count) }
        guard defaultSize > 0 else { throw UserFacingError.saving }
        return defaultSize
    }
    func fileSize(at url: URL) throws -> Int64 {
        if let data = writes[url] { return Int64(data.count) }
        guard defaultSize > 0 else { throw UserFacingError.saving }
        return defaultSize
    }
    func applyFileProtection(at url: URL) { protectedURLs.append(url) }
    func writeImmutable(_ data: Data, to url: URL) throws {
        guard writes[url] == nil else { throw UserFacingError.saving }
        writes[url] = data
    }
    func isValidJPEG(_ data: Data) -> Bool { validJPEG && !data.isEmpty }
    func setValidJPEG(_ value: Bool) { validJPEG = value }
}

actor TestAttachmentRegistration: AttachmentRegistrationSink {
    private(set) var attachments: [CandyCorn.Attachment] = []
    private var failuresRemaining: Int

    init(failuresRemaining: Int = 0) { self.failuresRemaining = failuresRemaining }

    func register(_ attachment: CandyCorn.Attachment) throws {
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw UserFacingError.saving
        }
        attachments.append(attachment)
    }
}

actor TestCheckpoint: RecordingCheckpointSink {
    private(set) var writes: [Int] = []
    private var failuresRemaining: Int

    init(failuresRemaining: Int = 0) { self.failuresRemaining = failuresRemaining }

    func write(appointmentID: UUID, durationMilliseconds: Int) throws {
        guard appointmentID == TestValues.appointmentID, durationMilliseconds >= 0 else { throw UserFacingError.saving }
        writes.append(durationMilliseconds)
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw UserFacingError.saving
        }
    }
}

struct FixedMediaClock: MediaClock {
    func wallNow() -> Date { Date(timeIntervalSince1970: 1_800_000_000) }
    func monotonicMilliseconds() -> Int64 { 10_000 }
    func sleep(milliseconds: Int) async throws {
        guard milliseconds > 0 else { throw CancellationError() }
        try await Task.sleep(for: .seconds(3_600))
    }
}
