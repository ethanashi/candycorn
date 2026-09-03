import Foundation

actor LocalPhotoAttachmentService: PhotoAttachmentService {
    private let attachments: any AttachmentStore
    private let registration: any AttachmentRegistrationSink
    private let logger: any EventLogging
    private let permission: any MediaPermissionClient
    private let files: any MediaFileClient
    private let clock: any MediaClock

    init(
        attachments: any AttachmentStore,
        registration: any AttachmentRegistrationSink,
        logger: any EventLogging,
        permission: any MediaPermissionClient = CameraPermissionClient(),
        files: any MediaFileClient = SystemMediaFileClient(),
        clock: any MediaClock = SystemMediaClock()
    ) {
        self.attachments = attachments
        self.registration = registration
        self.logger = logger
        self.permission = permission
        self.files = files
        self.clock = clock
    }

    func authorizationStatus() async -> CaptureAuthorization {
        await permission.authorizationStatus()
    }

    func requestPermission() async -> Bool {
        await permission.requestPermission()
    }

    func saveJPEG(_ data: Data, pixelWidth: Int, pixelHeight: Int) async throws -> Attachment {
        guard await permission.authorizationStatus() == .authorized else { throw UserFacingError.saving }
        guard !data.isEmpty, pixelWidth > 0, pixelHeight > 0 else { throw UserFacingError.saving }
        guard await files.isValidJPEG(data) else { throw UserFacingError.saving }
        do {
            let url = try await attachments.allocateURL(kind: .image, fileExtension: "jpg")
            try await files.writeImmutable(data, to: url)
            let byteCount = try await files.synchronizeAndFileSize(at: url)
            let attachment = Attachment(
                id: UUID(), kind: .image,
                relativePath: try MediaPath.relativePath(kind: .image, url: url),
                mediaType: "image/jpeg", byteCount: byteCount,
                durationMilliseconds: nil, createdAt: clock.wallNow(), isSample: false
            )
            try await registration.register(attachment)
            logger.record(.attachmentSaved, metrics: EventMetrics(count: 1))
            return attachment
        } catch {
            throw UserFacingError.saving
        }
    }
}
