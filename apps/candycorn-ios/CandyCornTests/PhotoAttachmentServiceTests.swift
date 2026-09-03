import Foundation
import Testing
@testable import CandyCorn

@Suite("Native photo attachment adapter")
struct PhotoAttachmentServiceTests {
    @Test("JPEG source is written immutably before registration")
    func immutableWrite() async throws {
        let files = TestMediaFiles(defaultSize: 0)
        let registration = TestAttachmentRegistration()
        let service = LocalPhotoAttachmentService(
            attachments: TestAttachmentStore(), registration: registration, logger: NoOpEventLogger(),
            permission: TestMediaPermission(status: .authorized), files: files, clock: FixedMediaClock()
        )
        let jpeg = Data([0xff, 0xd8, 0x01, 0x02, 0xff, 0xd9])
        let attachment = try await service.saveJPEG(jpeg, pixelWidth: 24, pixelHeight: 16)
        #expect(attachment.kind == .image)
        #expect(attachment.relativePath == "images/source.jpg")
        #expect(attachment.byteCount == Int64(jpeg.count))
        #expect(await files.writes[TestValues.imageURL] == jpeg)
        #expect(await registration.attachments == [attachment])
        await #expect(throws: UserFacingError.saving) {
            _ = try await service.saveJPEG(jpeg, pixelWidth: 24, pixelHeight: 16)
        }
        #expect(await registration.attachments.count == 1)
    }

    @Test("Permission, empty dimensions, and corrupt bytes are rejected")
    func validation() async {
        let permission = TestMediaPermission(status: .notDetermined, requestResult: false)
        let files = TestMediaFiles(defaultSize: 0)
        let service = LocalPhotoAttachmentService(
            attachments: TestAttachmentStore(), registration: TestAttachmentRegistration(), logger: NoOpEventLogger(),
            permission: permission, files: files, clock: FixedMediaClock()
        )
        #expect(await permission.requestCount == 0)
        #expect(await service.authorizationStatus() == .notDetermined)
        #expect(!(await service.requestPermission()))
        #expect(await permission.requestCount == 1)
        await #expect(throws: UserFacingError.saving) {
            _ = try await service.saveJPEG(Data([1]), pixelWidth: 1, pixelHeight: 1)
        }

        let authorized = LocalPhotoAttachmentService(
            attachments: TestAttachmentStore(), registration: TestAttachmentRegistration(), logger: NoOpEventLogger(),
            permission: TestMediaPermission(status: .authorized), files: files, clock: FixedMediaClock()
        )
        await files.setValidJPEG(false)
        await #expect(throws: UserFacingError.saving) {
            _ = try await authorized.saveJPEG(Data([1, 2, 3]), pixelWidth: 1, pixelHeight: 1)
        }
        await #expect(throws: UserFacingError.saving) {
            _ = try await authorized.saveJPEG(Data([1]), pixelWidth: 0, pixelHeight: 1)
        }
    }
}
