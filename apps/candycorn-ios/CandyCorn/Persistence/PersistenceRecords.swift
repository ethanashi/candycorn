import Foundation

enum VaultRepositoryError: Error, Equatable, Sendable {
    case corruptRecord(table: String, id: String)
    case invalidInput
    case databaseUnavailable
    case searchUnavailable
}

enum PersistenceCoding {
    static func encode<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        do {
            return try encoder.encode(value)
        } catch {
            throw VaultRepositoryError.invalidInput
        }
    }

    static func decode<Value: Decodable>(_ type: Value.Type, from data: Data, table: String, id: String) throws -> Value {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw VaultRepositoryError.corruptRecord(table: table, id: id)
        }
    }
}

struct JournalPersistenceRecord: Sendable {
    let value: JournalEntry
    let payload: Data
    let isSample: Bool

    init(_ value: JournalEntry, isSample: Bool) throws {
        guard !value.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VaultRepositoryError.invalidInput
        }
        self.value = value
        payload = try PersistenceCoding.encode(value)
        self.isSample = isSample
    }
}

struct MoodPersistenceRecord: Sendable {
    let value: MoodLog
    let payload: Data
    let isSample: Bool

    init(_ value: MoodLog, isSample: Bool) throws {
        let normalized = value.normalized()
        self.value = normalized
        payload = try PersistenceCoding.encode(normalized)
        self.isSample = isSample
    }
}

struct AppointmentPersistenceRecord: Sendable {
    let value: Appointment
    let payload: Data
    let isSample: Bool

    init(_ value: Appointment, isSample: Bool) throws {
        if let endedAt = value.endedAt, let startedAt = value.startedAt, endedAt < startedAt {
            throw VaultRepositoryError.invalidInput
        }
        self.value = value
        payload = try PersistenceCoding.encode(value)
        self.isSample = isSample
    }
}

struct GoalPersistenceRecord: Sendable {
    let value: Goal
    let payload: Data
    let isSample: Bool

    init(_ value: Goal, isSample: Bool) throws {
        guard !value.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VaultRepositoryError.invalidInput
        }
        self.value = value
        payload = try PersistenceCoding.encode(value)
        self.isSample = isSample
    }
}

struct GoalProgressPersistenceRecord: Sendable {
    let value: GoalProgress
    let payload: Data
    let isSample: Bool

    init(_ value: GoalProgress, isSample: Bool) throws {
        guard !value.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VaultRepositoryError.invalidInput
        }
        self.value = value
        payload = try PersistenceCoding.encode(value)
        self.isSample = isSample
    }
}

struct TalkingPointPersistenceRecord: Sendable {
    let value: TalkingPoint
    let payload: Data
    let isSample: Bool

    init(_ value: TalkingPoint, isSample: Bool) throws {
        guard !value.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VaultRepositoryError.invalidInput
        }
        self.value = value
        payload = try PersistenceCoding.encode(value)
        self.isSample = isSample
    }
}

struct ArtifactPersistenceRecord: Sendable {
    let value: AIArtifact
    let payload: Data
    let isSample: Bool

    init(_ value: AIArtifact, isSample: Bool) throws {
        guard !value.provider.isEmpty, !value.model.isEmpty, !value.sourceIDs.isEmpty else {
            throw VaultRepositoryError.invalidInput
        }
        self.value = value
        payload = try PersistenceCoding.encode(value)
        self.isSample = isSample
    }
}

struct AttachmentPersistenceRecord: Sendable {
    let value: Attachment
    let payload: Data

    init(_ value: Attachment) throws {
        guard value.byteCount >= 0, !value.relativePath.isEmpty, !value.mediaType.isEmpty else {
            throw VaultRepositoryError.invalidInput
        }
        self.value = value
        payload = try PersistenceCoding.encode(value)
    }
}

struct ProviderPersistenceRecord: Sendable {
    let value: ProviderProfile
    let payload: Data

    init(_ value: ProviderProfile) throws {
        guard !value.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VaultRepositoryError.invalidInput
        }
        self.value = value
        payload = try PersistenceCoding.encode(value)
    }
}

struct TranscriptPersistenceRecord: Sendable {
    let value: TranscriptSegment
    let payload: Data
    let isSample: Bool

    init(_ value: TranscriptSegment, isSample: Bool) throws {
        guard value.startMilliseconds >= 0, value.endMilliseconds > value.startMilliseconds else {
            throw VaultRepositoryError.invalidInput
        }
        self.value = value
        payload = try PersistenceCoding.encode(value)
        self.isSample = isSample
    }
}
