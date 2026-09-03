import AVFoundation
import Foundation
import ImageIO

private struct StoredObserverToken: @unchecked Sendable {
    let center: NotificationCenter
    let value: NSObjectProtocol
}

enum MediaSystemEvent: Sendable, Equatable {
    case interruptionBegan
    case routeChanged
}

protocol MediaPermissionClient: Sendable {
    func authorizationStatus() async -> CaptureAuthorization
    func requestPermission() async -> Bool
}

protocol MediaAudioSessionClient: Sendable {
    func beginRecording() async throws
    func endRecording() async
    func beginPlayback() async throws
    func endPlayback() async
    func hasInputRoute() async -> Bool
    func events() async -> AsyncStream<MediaSystemEvent>
}

protocol MediaRecorderClient: Sendable {
    func start() async -> Bool
    func stop() async
    func updateMeters() async
    func averagePower() async -> Float
    func durationMilliseconds() async -> Int
}

protocol MediaRecorderFactory: Sendable {
    func makeRecorder(url: URL, settings: [String: Sendable]) async throws -> any MediaRecorderClient
}

protocol MediaPlaybackClient: Sendable {
    func play() async -> Bool
    func pause() async
    func stop() async
    func currentMilliseconds() async -> Int
    func durationMilliseconds() async -> Int
    func isPlaying() async -> Bool
}

protocol MediaPlaybackFactory: Sendable {
    func makePlayer(url: URL) async throws -> any MediaPlaybackClient
}

protocol MediaFileClient: Sendable {
    func synchronizeAndFileSize(at url: URL) async throws -> Int64
    func fileSize(at url: URL) async throws -> Int64
    func applyFileProtection(at url: URL) async throws
    func writeImmutable(_ data: Data, to url: URL) async throws
    func isValidJPEG(_ data: Data) async -> Bool
}

protocol AttachmentRegistrationSink: Sendable {
    func register(_ attachment: Attachment) async throws
}

protocol RecordingCheckpointSink: Sendable {
    func write(appointmentID: UUID, durationMilliseconds: Int) async throws
}

protocol MediaClock: Sendable {
    func wallNow() -> Date
    func monotonicMilliseconds() -> Int64
    func sleep(milliseconds: Int) async throws
}

struct CareStoreAttachmentRegistrationSink: AttachmentRegistrationSink {
    let careStore: any CareStore

    func register(_ attachment: Attachment) async throws {
        try await careStore.saveAttachment(attachment)
    }
}

struct CareStoreRecordingCheckpointSink: RecordingCheckpointSink {
    let careStore: any CareStore
    let now: @Sendable () -> Date

    init(careStore: any CareStore, now: @escaping @Sendable () -> Date) {
        self.careStore = careStore
        self.now = now
    }

    func write(appointmentID: UUID, durationMilliseconds: Int) async throws {
        guard durationMilliseconds >= 0 else { throw UserFacingError.saving }
        let snapshot = try await careStore.snapshot()
        guard var appointment = snapshot.appointments.first(where: { $0.id == appointmentID }) else {
            throw UserFacingError.saving
        }

        if appointment.status != .recording || appointment.startedAt == nil {
            appointment.startedAt = now().addingTimeInterval(-TimeInterval(durationMilliseconds) / 1_000)
        }
        appointment.status = .recording
        try await careStore.saveAppointment(appointment)
    }
}

struct SystemMediaClock: MediaClock {
    func wallNow() -> Date { Date() }

    func monotonicMilliseconds() -> Int64 {
        Int64(DispatchTime.now().uptimeNanoseconds / 1_000_000)
    }

    func sleep(milliseconds: Int) async throws {
        guard milliseconds > 0 else { throw UserFacingError.recording }
        try await Task.sleep(for: .milliseconds(milliseconds))
    }
}

struct MicrophonePermissionClient: MediaPermissionClient {
    func authorizationStatus() -> CaptureAuthorization {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: .authorized
        case .denied: .denied
        case .undetermined: .notDetermined
        @unknown default: .restricted
        }
    }

    func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }
}

struct CameraPermissionClient: MediaPermissionClient {
    func authorizationStatus() -> CaptureAuthorization {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: .authorized
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .restricted
        }
    }

    func requestPermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }
}

actor SystemAudioSessionClient: MediaAudioSessionClient {
    static let shared = SystemAudioSessionClient()

    private let session: AVAudioSession
    private let eventStream: AsyncStream<MediaSystemEvent>
    private let eventContinuation: AsyncStream<MediaSystemEvent>.Continuation
    private var observerTokens: [StoredObserverToken] = []
    private var recordingActive = false
    private var playbackActive = false

    init(session: AVAudioSession = .sharedInstance(), center: NotificationCenter = .default) {
        self.session = session
        let pair = AsyncStream.makeStream(of: MediaSystemEvent.self, bufferingPolicy: .bufferingNewest(16))
        eventStream = pair.stream
        eventContinuation = pair.continuation
        let interruptionToken = center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: nil) { notification in
            guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            pair.continuation.yield(.interruptionBegan)
        }
        let routeToken = center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: nil) { _ in
            pair.continuation.yield(.routeChanged)
        }
        observerTokens = [
            StoredObserverToken(center: center, value: interruptionToken),
            StoredObserverToken(center: center, value: routeToken)
        ]
    }

    deinit {
        eventContinuation.finish()
        for token in observerTokens.prefix(16) {
            token.center.removeObserver(token.value)
        }
    }

    func beginRecording() throws {
        guard !recordingActive else { throw UserFacingError.recording }
        guard !playbackActive else { throw UserFacingError.recording }
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.allowBluetoothHFP, .defaultToSpeaker])
        try session.setActive(true)
        guard !session.currentRoute.inputs.isEmpty else {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw UserFacingError.recording
        }
        recordingActive = true
    }

    func endRecording() {
        guard recordingActive else { return }
        recordingActive = false
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    func beginPlayback() throws {
        guard !recordingActive else { throw UserFacingError.playback }
        guard !playbackActive else { return }
        try session.setCategory(.playback, mode: .spokenAudio)
        try session.setActive(true)
        playbackActive = true
    }

    func endPlayback() {
        guard playbackActive else { return }
        playbackActive = false
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    func hasInputRoute() -> Bool {
        !session.currentRoute.inputs.isEmpty
    }

    func events() -> AsyncStream<MediaSystemEvent> { eventStream }
}

actor SystemRecorderClient: MediaRecorderClient {
    private let recorder: AVAudioRecorder

    init(url: URL, settings: [String: Any]) throws {
        recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.prepareToRecord() else { throw UserFacingError.recording }
    }

    func start() -> Bool { recorder.record() }
    func stop() { recorder.stop() }
    func updateMeters() { recorder.updateMeters() }
    func averagePower() -> Float { recorder.averagePower(forChannel: 0) }
    func durationMilliseconds() -> Int { max(0, Int((recorder.currentTime * 1_000).rounded())) }
}

struct SystemRecorderFactory: MediaRecorderFactory {
    func makeRecorder(url: URL, settings: [String: Sendable]) async throws -> any MediaRecorderClient {
        guard url.isFileURL, !settings.isEmpty else { throw UserFacingError.recording }
        var values: [String: Any] = [:]
        for (key, value) in settings.prefix(16) {
            values[key] = value
        }
        return try SystemRecorderClient(url: url, settings: values)
    }
}

actor SystemPlaybackClient: MediaPlaybackClient {
    private let player: AVAudioPlayer

    init(url: URL) throws {
        player = try AVAudioPlayer(contentsOf: url)
        guard player.duration.isFinite, player.duration > 0, player.prepareToPlay() else {
            throw UserFacingError.playback
        }
    }

    func play() -> Bool { player.play() }
    func pause() { player.pause() }
    func stop() {
        player.stop()
        player.currentTime = 0
    }
    func currentMilliseconds() -> Int { max(0, Int((player.currentTime * 1_000).rounded())) }
    func durationMilliseconds() -> Int { max(0, Int((player.duration * 1_000).rounded())) }
    func isPlaying() -> Bool { player.isPlaying }
}

struct SystemPlaybackFactory: MediaPlaybackFactory {
    func makePlayer(url: URL) async throws -> any MediaPlaybackClient {
        guard url.isFileURL else { throw UserFacingError.playback }
        return try SystemPlaybackClient(url: url)
    }
}

struct SystemMediaFileClient: MediaFileClient {
    func synchronizeAndFileSize(at url: URL) throws -> Int64 {
        guard url.isFileURL else { throw UserFacingError.saving }
        let handle = try FileHandle(forUpdating: url)
        try handle.synchronize()
        try handle.close()
        return try fileSize(at: url)
    }

    func fileSize(at url: URL) throws -> Int64 {
        guard url.isFileURL else { throw UserFacingError.saving }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isReadableKey])
        guard values.isRegularFile == true, values.isReadable == true, let size = values.fileSize, size > 0 else {
            throw UserFacingError.saving
        }
        return Int64(size)
    }

    func applyFileProtection(at url: URL) throws {
        guard url.isFileURL else { throw UserFacingError.saving }
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
    }

    func writeImmutable(_ data: Data, to url: URL) throws {
        guard !data.isEmpty, url.isFileURL else { throw UserFacingError.saving }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .withoutOverwriting])
        try applyFileProtection(at: url)
    }

    func isValidJPEG(_ data: Data) -> Bool {
        guard data.count >= 4, data.starts(with: [0xff, 0xd8]), data.suffix(2) == Data([0xff, 0xd9]) else { return false }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) == 1 else { return false }
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) != nil
    }
}

enum MediaPath {
    static func relativePath(kind: AttachmentKind, url: URL) throws -> String {
        guard url.isFileURL, !url.lastPathComponent.isEmpty else { throw UserFacingError.saving }
        let directory = url.deletingLastPathComponent().lastPathComponent
        let expectedDirectory = switch kind {
        case .audio: "audio"
        case .image: "images"
        case .document: "documents"
        }
        guard directory == expectedDirectory else { throw UserFacingError.saving }
        return "\(directory)/\(url.lastPathComponent)"
    }
}
