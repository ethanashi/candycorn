import Foundation

enum AttachmentStoreError: Error, Equatable, Sendable {
    case invalidExtension
    case unsafePath
    case missingFile
    case fileOperationFailed
}

actor VaultAttachmentStore: AttachmentStore {
    private static let allowedExtensions: [AttachmentKind: Set<String>] = [
        .audio: ["m4a", "aac"],
        .image: ["jpg", "jpeg", "heic", "png"],
        .document: ["pdf", "txt", "md", "json"],
    ]
    let rootURL: URL

    init(rootURL: URL) throws {
        guard rootURL.isFileURL else { throw AttachmentStoreError.unsafePath }
        self.rootURL = rootURL.standardizedFileURL
        try Self.createDirectories(at: self.rootURL)
    }

    static func applicationSupport() throws -> VaultAttachmentStore {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw AttachmentStoreError.fileOperationFailed
        }
        return try VaultAttachmentStore(rootURL: support.appending(path: "CandyCorn/attachments", directoryHint: .isDirectory))
    }

    func allocateURL(kind: AttachmentKind, fileExtension: String) throws -> URL {
        let normalized = fileExtension.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard let allowed = Self.allowedExtensions[kind], allowed.contains(normalized) else {
            throw AttachmentStoreError.invalidExtension
        }
        let directory = rootURL.appending(path: Self.directoryName(for: kind), directoryHint: .isDirectory)
        let result = directory.appending(path: UUID().uuidString.lowercased()).appendingPathExtension(normalized)
        guard Self.isContained(result, by: rootURL) else { throw AttachmentStoreError.unsafePath }
        return result
    }

    func url(for attachment: Attachment) throws -> URL {
        guard !attachment.relativePath.isEmpty, !attachment.relativePath.hasPrefix("/") else {
            throw AttachmentStoreError.unsafePath
        }
        let candidate = rootURL.appending(path: attachment.relativePath).standardizedFileURL
        guard Self.isContained(candidate, by: rootURL) else { throw AttachmentStoreError.unsafePath }
        return candidate
    }

    func copyIntoExport(_ attachment: Attachment, destination: URL) throws {
        let source = try url(for: attachment)
        guard FileManager.default.fileExists(atPath: source.path) else { throw AttachmentStoreError.missingFile }
        guard destination.isFileURL else { throw AttachmentStoreError.unsafePath }
        let target = destination.appending(path: source.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
            try FileManager.default.copyItem(at: source, to: target)
            try Self.applyProtection(to: target)
        } catch {
            throw AttachmentStoreError.fileOperationFailed
        }
    }

    func removeAll() throws {
        do {
            if FileManager.default.fileExists(atPath: rootURL.path) { try FileManager.default.removeItem(at: rootURL) }
            try Self.createDirectories(at: rootURL)
        } catch {
            throw AttachmentStoreError.fileOperationFailed
        }
    }

    private static func directoryName(for kind: AttachmentKind) -> String {
        switch kind {
        case .audio: "audio"
        case .image: "images"
        case .document: "documents"
        }
    }

    private static func createDirectories(at root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for name in ["audio", "images", "documents"] {
            let directory = root.appending(path: name, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try applyProtection(to: directory)
        }
        try applyProtection(to: root)
    }

    private static func applyProtection(to url: URL) throws {
        try (url as NSURL).setResourceValue(URLFileProtection.completeUntilFirstUserAuthentication, forKey: .fileProtectionKey)
    }

    private static func isContained(_ candidate: URL, by root: URL) -> Bool {
        let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
        let candidatePath = candidate.resolvingSymlinksInPath().standardizedFileURL.path
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }
}
