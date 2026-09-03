import Foundation
import Testing
@testable import CandyCorn

@Suite("Vault security")
struct VaultSecurityTests {
    @Test("Attachment paths stay below the vault root")
    func attachmentPaths() async throws {
        let (root, _, _, attachments, _) = try VaultTestSupport.make()
        defer { VaultTestSupport.remove(root) }
        let allocated = try await attachments.allocateURL(kind: .audio, fileExtension: "m4a")
        #expect(allocated.path.hasPrefix(root.path))
        let unsafe = Attachment(id: UUID(), kind: .audio, relativePath: "../../outside.m4a", mediaType: "audio/mp4", byteCount: 1, durationMilliseconds: nil, createdAt: .now, isSample: false)
        var rejected = false
        do { _ = try await attachments.url(for: unsafe) } catch { rejected = true }
        #expect(rejected)
        await #expect(throws: AttachmentStoreError.self) {
            _ = try await attachments.allocateURL(kind: .audio, fileExtension: "exe")
        }
        try Data("audio".utf8).write(to: allocated)
        try await attachments.removeAll()
        #expect(!FileManager.default.fileExists(atPath: allocated.path))
    }

    @Test("Destructive recreation rotates the key and leaves an empty usable vault")
    func recreation() async throws {
        let (root, database, store, _, keyStore) = try VaultTestSupport.make()
        defer { VaultTestSupport.remove(root) }
        _ = try await store.snapshot()
        let oldKey = try keyStore.getOrCreateKey()
        try await database.destroyAndRecreateVault()
        let newKey = try keyStore.getOrCreateKey()
        let snapshot = try await store.snapshot()
        #expect(oldKey != newKey)
        #expect(snapshot == SeededData.emptySnapshot)
    }

    @Test("Production logger has no content-bearing API or interpolation")
    func loggerSourceIsScalarOnly() throws {
        let testsURL = URL(fileURLWithPath: #filePath)
        let appRoot = testsURL.deletingLastPathComponent().deletingLastPathComponent().appending(path: "CandyCorn")
        let source = try String(contentsOf: appRoot.appending(path: "Persistence/PrivacyEventLogger.swift"), encoding: .utf8)
        for forbidden in ["rawText", "cleanedText", "transcript", "note", "title", "talkingPoint", "payload", "relativePath", "fileURL"] {
            #expect(!source.contains(forbidden))
        }
        #expect(source.contains("EventName"))
        #expect(source.contains("EventMetrics"))
        guard let enumerator = FileManager.default.enumerator(at: appRoot, includingPropertiesForKeys: nil) else {
            Issue.record("Could not inspect production logging sources")
            return
        }
        let forbiddenFields = ["rawText", "cleanedText", "transcript", "note", "title", "talkingPoint", "payload", "relativePath", "fileURL"]
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            let fileSource = try String(contentsOf: fileURL, encoding: .utf8)
            for line in fileSource.split(separator: "\n") where line.contains(".record(") || line.contains("Logger(") {
                #expect(!forbiddenFields.contains { line.contains($0) })
            }
        }
    }
}
