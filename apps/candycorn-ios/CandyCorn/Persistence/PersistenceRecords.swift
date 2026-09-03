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
        let text = value.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let labelIsValid = value.rawSpeakerLabel.map {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ?? true
        let confidenceIsValid = value.confidence.map { $0.isFinite && (0...1).contains($0) } ?? true
        guard !text.isEmpty, labelIsValid, confidenceIsValid,
              value.startMilliseconds >= 0, value.endMilliseconds > value.startMilliseconds else {
            throw VaultRepositoryError.invalidInput
        }
        self.value = value
        payload = try PersistenceCoding.encode(value)
        self.isSample = isSample
    }
}

struct SessionProcessingPersistenceRecord: Sendable {
    let value: SessionProcessingRecord
    let payload: Data

    init(_ value: SessionProcessingRecord) throws {
        let progressIsValid = value.progress.map { $0.isFinite && (0...1).contains($0) } ?? true
        let failureIsValid = value.failure.map {
            !$0.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ?? true
        guard progressIsValid, failureIsValid else { throw VaultRepositoryError.invalidInput }
        self.value = value
        payload = try PersistenceCoding.encode(value)
    }
}

struct SpeakerAssignmentPersistenceRecord: Sendable {
    let value: SpeakerClusterAssignment
    let payload: Data

    init(_ value: SpeakerClusterAssignment) throws {
        let label = value.rawSpeakerLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty, label == value.rawSpeakerLabel,
              label.count <= 200, value.speaker != .unknown else {
            throw VaultRepositoryError.invalidInput
        }
        self.value = value
        payload = try PersistenceCoding.encode(value)
    }
}

struct SpeakerEmbeddingPersistenceRecord: Sendable {
    static let maximumDimensions = 4_096

    let appointmentID: UUID
    let value: SpeakerEmbedding
    let payload: Data

    init(_ value: SpeakerEmbedding, appointmentID: UUID) throws {
        let label = value.rawSpeakerLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelID = value.modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty, label == value.rawSpeakerLabel, label.count <= 200,
              !modelID.isEmpty, modelID == value.modelID, modelID.count <= 200,
              (1...Self.maximumDimensions).contains(value.values.count),
              value.values.allSatisfy(\.isFinite) else {
            throw VaultRepositoryError.invalidInput
        }
        self.appointmentID = appointmentID
        self.value = value
        payload = try PersistenceCoding.encode(value)
    }
}

struct PatientVoiceProfilePersistenceRecord: Sendable {
    let value: PatientVoiceProfile
    let payload: Data

    init(_ value: PatientVoiceProfile) throws {
        let modelID = value.modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelID.isEmpty, modelID == value.modelID, modelID.count <= 200,
              (1...SpeakerEmbeddingPersistenceRecord.maximumDimensions).contains(value.embedding.count),
              value.embedding.allSatisfy(\.isFinite) else {
            throw VaultRepositoryError.invalidInput
        }
        self.value = value
        payload = try PersistenceCoding.encode(value)
    }
}

struct SessionDebriefDecisionPersistenceRecord: Sendable {
    let value: SessionDebriefDecision
    let payload: Data

    init(_ value: SessionDebriefDecision) throws {
        let editedTextIsValid = value.editedText.map {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ?? true
        guard editedTextIsValid else { throw VaultRepositoryError.invalidInput }
        self.value = value
        payload = try PersistenceCoding.encode(value)
    }
}
