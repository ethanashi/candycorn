import Foundation
import GRDB

actor VaultRepositories: CareStore {
    private let database: VaultDatabase
    private let attachments: (any AttachmentStore)?
    private let logger: any EventLogging

    init(database: VaultDatabase, attachments: (any AttachmentStore)? = nil, logger: any EventLogging = PrivacyEventLogger()) {
        self.database = database
        self.attachments = attachments
        self.logger = logger
    }

    func snapshot() async throws -> CareSnapshot {
        try await database.write { db in
            try SampleContentSeeder.prepareIfNeeded(in: db)
        }
        return try await database.read { db in
            CareSnapshot(
                journals: try Self.fetch(JournalEntry.self, table: "journal_entries", order: "created_at DESC, id", db: db),
                moods: try Self.fetch(MoodLog.self, table: "mood_logs", order: "created_at DESC, id", db: db),
                appointments: try Self.fetch(Appointment.self, table: "appointments", order: "COALESCE(started_at, scheduled_at, 0) DESC, id", db: db),
                goals: try Self.fetch(Goal.self, table: "goals", order: "created_at DESC, id", db: db),
                goalProgress: try Self.fetch(GoalProgress.self, table: "goal_progress", order: "created_at DESC, id", db: db),
                talkingPoints: try Self.fetch(TalkingPoint.self, table: "talking_points", order: "created_at DESC, id", db: db),
                artifacts: try Self.fetch(AIArtifact.self, table: "ai_artifacts", order: "created_at DESC, id", db: db),
                attachments: try Self.fetch(Attachment.self, table: "attachments", order: "created_at DESC, id", db: db),
                providers: try Self.fetch(ProviderProfile.self, table: "providers", order: "name COLLATE NOCASE, id", db: db),
                transcript: try Self.fetch(TranscriptSegment.self, table: "transcript_segments", order: "appointment_id, start_milliseconds, id", db: db),
                settings: try Self.fetchSettings(db),
                sessionProcessing: try Self.fetch(SessionProcessingRecord.self, table: "session_processing", order: "updated_at DESC, id", db: db),
                speakerAssignments: try Self.fetch(SpeakerClusterAssignment.self, table: "speaker_cluster_assignments", order: "appointment_id, raw_speaker_label, id", db: db),
                speakerEmbeddings: try Self.fetchPayloads(SpeakerEmbedding.self, table: "speaker_embeddings", identity: "appointment_id || ':' || raw_speaker_label || ':' || model_id", order: "appointment_id, raw_speaker_label, model_id", db: db),
                patientVoiceProfiles: try Self.fetch(PatientVoiceProfile.self, table: "patient_voice_profiles", order: "created_at DESC, id", db: db),
                debriefDecisions: try Self.fetch(SessionDebriefDecision.self, table: "session_debrief_decisions", order: "created_at, id", db: db)
            )
        }
    }

    func saveJournal(_ entry: JournalEntry) async throws {
        let record = try JournalPersistenceRecord(entry, isSample: false)
        try await database.write { db in try VaultRecordWriter.save(record, in: db) }
        logger.record(.journalSaved, metrics: EventMetrics(count: 1))
    }

    func deleteJournal(id: UUID) async throws {
        try await database.write { db in
            try db.execute(sql: "DELETE FROM journal_entries WHERE id = ?", arguments: [id.uuidString.lowercased()])
            if try Self.hasSearchTable(db) {
                try db.execute(sql: "DELETE FROM care_search WHERE kind = 'journal' AND entity_id = ?", arguments: [id.uuidString.lowercased()])
            }
        }
    }

    func saveMood(_ mood: MoodLog) async throws {
        let record = try MoodPersistenceRecord(mood, isSample: false)
        try await database.write { db in try VaultRecordWriter.save(record, in: db) }
        logger.record(.moodSaved, metrics: EventMetrics(count: 1))
    }

    func saveAppointment(_ appointment: Appointment) async throws {
        let record = try AppointmentPersistenceRecord(appointment, isSample: false)
        try await database.write { db in try VaultRecordWriter.save(record, in: db) }
    }

    func saveGoal(_ goal: Goal) async throws {
        let record = try GoalPersistenceRecord(goal, isSample: false)
        try await database.write { db in try VaultRecordWriter.save(record, in: db) }
    }

    func addGoalProgress(_ progress: GoalProgress) async throws {
        let record = try GoalProgressPersistenceRecord(progress, isSample: false)
        try await database.write { db in try VaultRecordWriter.save(record, in: db) }
    }

    func saveTalkingPoint(_ point: TalkingPoint) async throws {
        let record = try TalkingPointPersistenceRecord(point, isSample: false)
        try await database.write { db in try VaultRecordWriter.save(record, in: db) }
    }

    func saveAttachment(_ attachment: Attachment) async throws {
        let record = try AttachmentPersistenceRecord(attachment)
        try await database.write { db in try VaultRecordWriter.save(record, in: db) }
        logger.record(.attachmentSaved, metrics: EventMetrics(count: 1))
    }

    func saveArtifact(_ artifact: AIArtifact) async throws {
        let record = try ArtifactPersistenceRecord(artifact, isSample: false)
        try await database.write { db in
            try VaultRecordWriter.save(record, in: db)
        }
    }

    func deleteArtifact(id: UUID) async throws {
        try await database.write { db in
            try db.execute(
                sql: "DELETE FROM ai_artifacts WHERE id = ?",
                arguments: [id.uuidString.lowercased()]
            )
        }
    }

    func replaceTranscriptSegments(_ segments: [TranscriptSegment], for appointmentID: UUID) async throws {
        guard segments.count <= 100_000 else { throw VaultRepositoryError.invalidInput }
        let records = try segments.map { try TranscriptPersistenceRecord($0, isSample: false) }
        guard records.allSatisfy({ $0.value.appointmentID == appointmentID }) else {
            throw VaultRepositoryError.invalidInput
        }
        guard Set(records.map(\.value.id)).count == records.count else {
            throw VaultRepositoryError.invalidInput
        }
        try await database.write { db in
            let appointment = try Self.appointment(for: appointmentID, db: db)
            try db.execute(sql: "DELETE FROM transcript_segments WHERE appointment_id = ?", arguments: [Self.uuid(appointmentID)])
            for record in records.prefix(100_000) {
                try VaultRecordWriter.save(record, in: db, insertOnly: true)
            }
            let body = records.map(\.value.text).joined(separator: " ")
            try VaultRecordWriter.replaceIndex(
                kind: .transcript,
                id: appointmentID,
                title: "\(appointment.kind.displayName) transcript",
                body: body,
                date: appointment.startedAt ?? appointment.scheduledAt ?? .distantPast,
                db: db
            )
        }
    }

    func saveSpeakerEmbeddings(_ embeddings: [SpeakerEmbedding], for appointmentID: UUID) async throws {
        guard (1...256).contains(embeddings.count) else { throw VaultRepositoryError.invalidInput }
        let records = try embeddings.map { try SpeakerEmbeddingPersistenceRecord($0, appointmentID: appointmentID) }
        let identities = records.map {
            "\($0.value.rawSpeakerLabel.utf8.count)#\($0.value.rawSpeakerLabel)\($0.value.modelID)"
        }
        guard Set(identities).count == identities.count else { throw VaultRepositoryError.invalidInput }
        try await database.write { db in
            _ = try Self.appointment(for: appointmentID, db: db)
            try db.execute(sql: "DELETE FROM speaker_embeddings WHERE appointment_id = ?", arguments: [Self.uuid(appointmentID)])
            for record in records.prefix(256) {
                try VaultRecordWriter.save(record, in: db)
            }
        }
    }

    func assignSpeakerCluster(_ assignment: SpeakerClusterAssignment, rememberPatientVoice: Bool) async throws {
        let record = try SpeakerAssignmentPersistenceRecord(assignment)
        guard !rememberPatientVoice || assignment.speaker == .patient else {
            throw VaultRepositoryError.invalidInput
        }
        try await database.write { db in
            _ = try Self.appointment(for: assignment.appointmentID, db: db)
            let existingID = try String.fetchOne(
                db,
                sql: "SELECT id FROM speaker_cluster_assignments WHERE appointment_id = ? AND raw_speaker_label = ?",
                arguments: [Self.uuid(assignment.appointmentID), assignment.rawSpeakerLabel]
            )
            guard existingID == nil || existingID == Self.uuid(assignment.id) else {
                throw VaultRepositoryError.invalidInput
            }
            try VaultRecordWriter.save(record, in: db)
            try Self.relabelTranscript(for: assignment, db: db)
            if rememberPatientVoice {
                try Self.rememberPatientProfile(for: assignment, db: db)
            }
        }
    }

    func saveSessionProcessing(_ record: SessionProcessingRecord) async throws {
        let persistence = try SessionProcessingPersistenceRecord(record)
        try await database.write { db in
            _ = try Self.appointment(for: record.appointmentID, db: db)
            try VaultRecordWriter.save(persistence, in: db)
        }
    }

    func applySessionDebriefMutation(_ mutation: SessionDebriefMutation) async throws {
        let decision = try Self.validate(mutation)
        let record = try SessionDebriefDecisionPersistenceRecord(decision)
        try await database.write { db in
            _ = try Self.appointment(for: decision.appointmentID, db: db)
            guard try VaultRecordWriter.insert(record, in: db) else { return }
            try Self.apply(mutation, db: db)
        }
    }

    func search(_ query: String, limit: Int) async throws -> [SearchHit] {
        let normalized = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        guard !normalized.isEmpty, (1...100).contains(limit) else { throw VaultRepositoryError.invalidInput }
        let terms = Self.searchTerms(normalized)
        guard !terms.isEmpty else { return [] }
        let hits = try await database.read { db in
            if try Self.hasSearchTable(db) {
                do {
                    return try Self.ftsSearch(terms: terms, limit: limit, db: db)
                } catch let error as VaultRepositoryError {
                    throw error
                } catch { }
            }
            return try Self.likeSearch(terms: terms, limit: limit, db: db)
        }
        logger.record(.searchCompleted, metrics: EventMetrics(count: hits.count))
        return hits
    }

    func setSampleContentEnabled(_ enabled: Bool) async throws {
        try await database.write { db in
            if enabled {
                try SampleContentSeeder.seed(in: db)
            } else {
                try SampleContentSeeder.remove(in: db)
            }
            var settings = try Self.fetchSettings(db)
            settings.useSampleContent = enabled
            try VaultRecordWriter.saveSettings(settings, in: db)
        }
        if !enabled, let attachments {
            let snapshot = try await snapshot()
            for attachment in SeededData.attachments where !snapshot.attachments.contains(where: { $0.id == attachment.id }) {
                let url = try await attachments.url(for: attachment)
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            }
        }
    }

    func updateSettings(_ settings: VaultSettings) async throws {
        try await database.write { db in try VaultRecordWriter.saveSettings(settings, in: db) }
    }

    private static func fetch<Value: Decodable>(
        _ type: Value.Type,
        table: String,
        order: String,
        db: Database
    ) throws -> [Value] {
        let rows = try Row.fetchAll(db, sql: "SELECT id, payload FROM \(table) ORDER BY \(order)")
        return try rows.map { row in
            let id: String = row["id"]
            let payload: Data = row["payload"]
            return try PersistenceCoding.decode(type, from: payload, table: table, id: id)
        }
    }

    private static func fetchPayloads<Value: Decodable>(
        _ type: Value.Type,
        table: String,
        identity: String,
        order: String,
        db: Database
    ) throws -> [Value] {
        let rows = try Row.fetchAll(db, sql: "SELECT \(identity) AS record_id, payload FROM \(table) ORDER BY \(order)")
        return try rows.map { row in
            let id: String = row["record_id"]
            let payload: Data = row["payload"]
            return try PersistenceCoding.decode(type, from: payload, table: table, id: id)
        }
    }

    private static func appointment(for id: UUID, db: Database) throws -> Appointment {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT payload FROM appointments WHERE id = ?",
            arguments: [uuid(id)]
        ) else { throw VaultRepositoryError.invalidInput }
        let payload: Data = row["payload"]
        return try PersistenceCoding.decode(Appointment.self, from: payload, table: "appointments", id: uuid(id))
    }

    private static func relabelTranscript(for assignment: SpeakerClusterAssignment, db: Database) throws {
        let rows = try Row.fetchAll(
            db,
            sql: "SELECT id, is_sample, payload FROM transcript_segments WHERE appointment_id = ? ORDER BY start_milliseconds, id",
            arguments: [uuid(assignment.appointmentID)]
        )
        guard rows.count <= 100_000 else { throw VaultRepositoryError.invalidInput }
        for row in rows.prefix(100_000) {
            let id: String = row["id"]
            let isSample: Bool = row["is_sample"]
            let payload: Data = row["payload"]
            var segment = try PersistenceCoding.decode(TranscriptSegment.self, from: payload, table: "transcript_segments", id: id)
            guard segment.rawSpeakerLabel == assignment.rawSpeakerLabel else { continue }
            segment.speaker = assignment.speaker
            try VaultRecordWriter.save(try TranscriptPersistenceRecord(segment, isSample: isSample), in: db)
        }
    }

    private static func rememberPatientProfile(for assignment: SpeakerClusterAssignment, db: Database) throws {
        let rows = try Row.fetchAll(
            db,
            sql: "SELECT model_id, payload FROM speaker_embeddings WHERE appointment_id = ? AND raw_speaker_label = ? ORDER BY model_id LIMIT 2",
            arguments: [uuid(assignment.appointmentID), assignment.rawSpeakerLabel]
        )
        guard rows.count == 1, let row = rows.first else { throw VaultRepositoryError.invalidInput }
        let modelID: String = row["model_id"]
        let payload: Data = row["payload"]
        let embedding = try PersistenceCoding.decode(SpeakerEmbedding.self, from: payload, table: "speaker_embeddings", id: modelID)
        let profile = PatientVoiceProfile(id: assignment.id, modelID: embedding.modelID, embedding: embedding.values, createdAt: assignment.updatedAt)
        try VaultRecordWriter.save(try PatientVoiceProfilePersistenceRecord(profile), in: db)
    }

    private static func validate(_ mutation: SessionDebriefMutation) throws -> SessionDebriefDecision {
        switch mutation {
        case let .addGoal(decision, goal):
            let validKind = decision.kind == .addedGoal || decision.kind == .addedHomework
            let validCadence = decision.kind != .addedHomework || goal.cadence == .homework
            let validProviderSource = decision.kind != .addedHomework
                || (goal.source == .providerExplicit && goal.provenance.voice == .provider)
            guard validKind, validCadence, validProviderSource, decision.targetEntityID == goal.id,
                  goal.sourceEntityID == decision.appointmentID else { throw VaultRepositoryError.invalidInput }
            return decision
        case let .ignoreGoal(decision):
            guard decision.kind == .ignoredGoal, decision.targetEntityID == nil else { throw VaultRepositoryError.invalidInput }
            return decision
        case let .markTalkingPointDiscussed(decision, point):
            guard decision.kind == .markedTalkingPointDiscussed,
                  decision.targetEntityID == point.id, point.status == .discussed else { throw VaultRepositoryError.invalidInput }
            return decision
        case let .pinQuestion(decision, point):
            guard decision.kind == .pinnedQuestion, decision.targetEntityID == point.id,
                  point.sourceID == decision.appointmentID, point.status == .open else { throw VaultRepositoryError.invalidInput }
            return decision
        }
    }

    private static func apply(_ mutation: SessionDebriefMutation, db: Database) throws {
        switch mutation {
        case let .addGoal(_, goal):
            guard try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM goals WHERE id = ?", arguments: [uuid(goal.id)]) == 0 else {
                throw VaultRepositoryError.invalidInput
            }
            try VaultRecordWriter.save(try GoalPersistenceRecord(goal, isSample: false), in: db, insertOnly: true)
        case .ignoreGoal:
            return
        case let .markTalkingPointDiscussed(_, point):
            guard try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM talking_points WHERE id = ?", arguments: [uuid(point.id)]) == 1 else {
                throw VaultRepositoryError.invalidInput
            }
            try VaultRecordWriter.save(try TalkingPointPersistenceRecord(point, isSample: false), in: db)
        case let .pinQuestion(_, point):
            guard try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM talking_points WHERE id = ?", arguments: [uuid(point.id)]) == 0 else {
                throw VaultRepositoryError.invalidInput
            }
            try VaultRecordWriter.save(try TalkingPointPersistenceRecord(point, isSample: false), in: db, insertOnly: true)
        }
    }

    private static func uuid(_ value: UUID) -> String {
        value.uuidString.lowercased()
    }

    private static func fetchSettings(_ db: Database) throws -> VaultSettings {
        guard let row = try Row.fetchOne(db, sql: "SELECT payload FROM app_settings WHERE id = 1") else {
            let settings = VaultSettings(useSampleContent: true, audioRetention: .ask, aiMode: .off, aiProvider: .off)
            try VaultRecordWriter.saveSettings(settings, in: db)
            return settings
        }
        let payload: Data = row["payload"]
        return try PersistenceCoding.decode(VaultSettings.self, from: payload, table: "app_settings", id: "1")
    }

    private static func hasSearchTable(_ db: Database) throws -> Bool {
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'care_search'") == 1
    }

    private static func searchTerms(_ query: String) -> [String] {
        let parts = query.unicodeScalars.split { !CharacterSet.alphanumerics.contains($0) }
        let operators = Set(["and", "or", "not", "near"])
        var terms: [String] = []
        for part in parts.prefix(200) {
            let term = String(part).lowercased()
            guard term.count > 1, !operators.contains(term), !terms.contains(term) else { continue }
            terms.append(term)
            if terms.count == 20 { break }
        }
        return terms
    }

    private static func ftsSearch(terms: [String], limit: Int, db: Database) throws -> [SearchHit] {
        let pattern = terms.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }.joined(separator: " AND ")
        let rows = try Row.fetchAll(db, sql: """
            SELECT kind, entity_id, title, body, CAST(occurred_at AS REAL) AS occurred_at
            FROM care_search WHERE care_search MATCH ?
            ORDER BY occurred_at DESC, entity_id ASC LIMIT ?
            """, arguments: [pattern, limit])
        return try rows.map(Self.hit(from:))
    }

    private static func likeSearch(terms: [String], limit: Int, db: Database) throws -> [SearchHit] {
        let predicate = Array(repeating: "(title LIKE ? ESCAPE '\\' COLLATE NOCASE OR body LIKE ? ESCAPE '\\' COLLATE NOCASE)", count: terms.count)
            .joined(separator: " AND ")
        var arguments = StatementArguments()
        for term in terms {
            let escaped = term.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "%", with: "\\%")
                .replacingOccurrences(of: "_", with: "\\_")
            let pattern = "%\(escaped)%"
            arguments += [pattern, pattern]
        }
        arguments += [limit]
        let rows = try Row.fetchAll(db, sql: """
            SELECT kind, entity_id, title, body, occurred_at FROM (
                SELECT 'journal' kind, id entity_id, title,
                       TRIM(raw_text || ' ' || COALESCE(cleaned_text, '') || ' ' || summary_text) body,
                       created_at occurred_at
                  FROM journal_entries
                UNION ALL
                SELECT 'goal', id, title, COALESCE(detail, title), created_at FROM goals
                UNION ALL
                SELECT 'talkingPoint', id, 'Bring up next time', text, created_at FROM talking_points
            ) searchable
            WHERE \(predicate)
            ORDER BY occurred_at DESC, entity_id ASC LIMIT ?
            """, arguments: arguments)
        return try rows.map(Self.hit(from:))
    }

    private static func hit(from row: Row) throws -> SearchHit {
        let kindValue: String = row["kind"]
        let entityValue: String = row["entity_id"]
        guard let kind = SearchEntityKind(rawValue: kindValue), let entityID = UUID(uuidString: entityValue) else {
            throw VaultRepositoryError.corruptRecord(table: "care_search", id: entityValue)
        }
        let title: String = row["title"]
        let body: String = row["body"]
        let timestamp: Double = row["occurred_at"]
        let excerpt = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return SearchHit(
            id: "\(kind.rawValue):\(entityID.uuidString.lowercased())",
            entityID: entityID,
            kind: kind,
            title: title,
            excerpt: excerpt.isEmpty ? "Saved on this device" : String(excerpt.prefix(240)),
            occurredAt: Date(timeIntervalSince1970: timestamp)
        )
    }
}

enum VaultRecordWriter {
    static func save(_ record: JournalPersistenceRecord, in db: Database, insertOnly: Bool = false) throws {
        let value = record.value
        try db.execute(sql: insertSQL(table: "journal_entries", columns: "id, created_at, updated_at, title, raw_text, cleaned_text, summary_text, original_attachment_id, audio_attachment_id, mood_log_id, is_sample, payload", updates: "created_at=excluded.created_at, updated_at=excluded.updated_at, title=excluded.title, raw_text=excluded.raw_text, cleaned_text=excluded.cleaned_text, summary_text=excluded.summary_text, original_attachment_id=excluded.original_attachment_id, audio_attachment_id=excluded.audio_attachment_id, mood_log_id=excluded.mood_log_id, payload=excluded.payload", count: 12, insertOnly: insertOnly), arguments: [uuid(value.id), timestamp(value.createdAt), timestamp(value.updatedAt), value.title, value.rawText, value.cleanedText, value.summaryItems.joined(separator: "\n"), optionalUUID(value.originalAttachmentID), optionalUUID(value.audioAttachmentID), optionalUUID(value.moodLogID), record.isSample, record.payload])
        guard !insertOnly || db.changesCount == 1 else { return }
        try index(kind: .journal, id: value.id, title: value.title, body: [value.rawText, value.cleanedText ?? "", value.summaryItems.joined(separator: " ")].joined(separator: " "), date: value.createdAt, db: db)
    }

    static func save(_ record: MoodPersistenceRecord, in db: Database, insertOnly: Bool = false) throws {
        let value = record.value
        try db.execute(sql: insertSQL(table: "mood_logs", columns: "id, created_at, note, is_sample, payload", updates: "created_at=excluded.created_at, note=excluded.note, payload=excluded.payload", count: 5, insertOnly: insertOnly), arguments: [uuid(value.id), timestamp(value.createdAt), value.note, record.isSample, record.payload])
    }

    static func save(_ record: AppointmentPersistenceRecord, in db: Database, insertOnly: Bool = false) throws {
        let value = record.value
        try db.execute(sql: insertSQL(table: "appointments", columns: "id, provider_id, scheduled_at, started_at, ended_at, status, manual_notes, is_sample, payload", updates: "provider_id=excluded.provider_id, scheduled_at=excluded.scheduled_at, started_at=excluded.started_at, ended_at=excluded.ended_at, status=excluded.status, manual_notes=excluded.manual_notes, payload=excluded.payload", count: 9, insertOnly: insertOnly), arguments: [uuid(value.id), optionalUUID(value.providerID), optionalTimestamp(value.scheduledAt), optionalTimestamp(value.startedAt), optionalTimestamp(value.endedAt), value.status.rawValue, value.manualNotes, record.isSample, record.payload])
    }

    static func save(_ record: GoalPersistenceRecord, in db: Database, insertOnly: Bool = false) throws {
        let value = record.value
        try db.execute(sql: insertSQL(table: "goals", columns: "id, created_at, title, detail, status, source_entity_id, is_sample, payload", updates: "created_at=excluded.created_at, title=excluded.title, detail=excluded.detail, status=excluded.status, source_entity_id=excluded.source_entity_id, payload=excluded.payload", count: 8, insertOnly: insertOnly), arguments: [uuid(value.id), timestamp(value.createdAt), value.title, value.detail, value.status.rawValue, optionalUUID(value.sourceEntityID), record.isSample, record.payload])
        guard !insertOnly || db.changesCount == 1 else { return }
        try index(kind: .goal, id: value.id, title: value.title, body: value.detail ?? value.title, date: value.createdAt, db: db)
    }

    static func save(_ record: GoalProgressPersistenceRecord, in db: Database, insertOnly: Bool = false) throws {
        let value = record.value
        try db.execute(sql: insertSQL(table: "goal_progress", columns: "id, goal_id, source_entry_id, created_at, is_sample, payload", updates: "goal_id=excluded.goal_id, source_entry_id=excluded.source_entry_id, created_at=excluded.created_at, payload=excluded.payload", count: 6, insertOnly: insertOnly), arguments: [uuid(value.id), uuid(value.goalID), optionalUUID(value.sourceEntryID), timestamp(value.createdAt), record.isSample, record.payload])
    }

    static func save(_ record: TalkingPointPersistenceRecord, in db: Database, insertOnly: Bool = false) throws {
        let value = record.value
        try db.execute(sql: insertSQL(table: "talking_points", columns: "id, created_at, text, status, source_id, is_sample, payload", updates: "created_at=excluded.created_at, text=excluded.text, status=excluded.status, source_id=excluded.source_id, payload=excluded.payload", count: 7, insertOnly: insertOnly), arguments: [uuid(value.id), timestamp(value.createdAt), value.text, value.status.rawValue, optionalUUID(value.sourceID), record.isSample, record.payload])
        guard !insertOnly || db.changesCount == 1 else { return }
        try index(kind: .talkingPoint, id: value.id, title: "Bring up next time", body: value.text, date: value.createdAt, db: db)
    }

    static func save(_ record: ArtifactPersistenceRecord, in db: Database, insertOnly: Bool = false) throws {
        let value = record.value
        try db.execute(sql: insertSQL(table: "ai_artifacts", columns: "id, kind, provider, model, created_at, is_sample, payload", updates: "kind=excluded.kind, provider=excluded.provider, model=excluded.model, created_at=excluded.created_at, payload=excluded.payload", count: 7, insertOnly: insertOnly), arguments: [uuid(value.id), value.kind.rawValue, value.provider, value.model, timestamp(value.createdAt), record.isSample, record.payload])
        guard !insertOnly || db.changesCount == 1 else { return }
        if !insertOnly {
            try db.execute(sql: "DELETE FROM ai_artifact_sources WHERE artifact_id = ?", arguments: [uuid(value.id)])
        }
        for (position, sourceID) in value.sourceIDs.enumerated() {
            try db.execute(sql: "INSERT OR IGNORE INTO ai_artifact_sources (artifact_id, source_id, position) VALUES (?, ?, ?)", arguments: [uuid(value.id), uuid(sourceID), position])
        }
    }

    static func save(_ record: AttachmentPersistenceRecord, in db: Database, insertOnly: Bool = false) throws {
        let value = record.value
        try db.execute(sql: insertSQL(table: "attachments", columns: "id, kind, relative_path, media_type, byte_count, duration_milliseconds, created_at, is_sample, payload", updates: "kind=excluded.kind, relative_path=excluded.relative_path, media_type=excluded.media_type, byte_count=excluded.byte_count, duration_milliseconds=excluded.duration_milliseconds, created_at=excluded.created_at, payload=excluded.payload", count: 9, insertOnly: insertOnly), arguments: [uuid(value.id), value.kind.rawValue, value.relativePath, value.mediaType, value.byteCount, value.durationMilliseconds, timestamp(value.createdAt), value.isSample, record.payload])
    }

    static func save(_ record: ProviderPersistenceRecord, in db: Database, insertOnly: Bool = false) throws {
        let value = record.value
        try db.execute(sql: insertSQL(table: "providers", columns: "id, name, appointment_kind, is_sample, payload", updates: "name=excluded.name, appointment_kind=excluded.appointment_kind, payload=excluded.payload", count: 5, insertOnly: insertOnly), arguments: [uuid(value.id), value.name, value.appointmentKind.rawValue, value.isSample, record.payload])
    }

    static func save(_ record: TranscriptPersistenceRecord, in db: Database, insertOnly: Bool = false) throws {
        let value = record.value
        try db.execute(sql: insertSQL(table: "transcript_segments", columns: "id, appointment_id, start_milliseconds, end_milliseconds, is_sample, payload", updates: "appointment_id=excluded.appointment_id, start_milliseconds=excluded.start_milliseconds, end_milliseconds=excluded.end_milliseconds, payload=excluded.payload", count: 6, insertOnly: insertOnly), arguments: [uuid(value.id), uuid(value.appointmentID), value.startMilliseconds, value.endMilliseconds, record.isSample, record.payload])
    }

    static func save(_ record: SessionProcessingPersistenceRecord, in db: Database) throws {
        let value = record.value
        try db.execute(sql: """
            INSERT INTO session_processing
                (id, appointment_id, stage, progress, summary_consent_granted, updated_at, payload)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(appointment_id) DO UPDATE SET
                id=excluded.id, stage=excluded.stage, progress=excluded.progress,
                summary_consent_granted=excluded.summary_consent_granted,
                updated_at=excluded.updated_at, payload=excluded.payload
            """, arguments: [uuid(value.id), uuid(value.appointmentID), value.stage.rawValue, value.progress, value.summaryConsentGranted, timestamp(value.updatedAt), record.payload])
    }

    static func save(_ record: SpeakerAssignmentPersistenceRecord, in db: Database) throws {
        let value = record.value
        try db.execute(sql: """
            INSERT INTO speaker_cluster_assignments
                (id, appointment_id, raw_speaker_label, speaker, updated_at, payload)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(appointment_id, raw_speaker_label) DO UPDATE SET
                speaker=excluded.speaker,
                updated_at=excluded.updated_at, payload=excluded.payload
            """, arguments: [uuid(value.id), uuid(value.appointmentID), value.rawSpeakerLabel, value.speaker.rawValue, timestamp(value.updatedAt), record.payload])
    }

    static func save(_ record: SpeakerEmbeddingPersistenceRecord, in db: Database) throws {
        let value = record.value
        try db.execute(sql: """
            INSERT INTO speaker_embeddings
                (appointment_id, raw_speaker_label, model_id, dimensions, payload)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(appointment_id, raw_speaker_label, model_id) DO UPDATE SET
                dimensions=excluded.dimensions, payload=excluded.payload
            """, arguments: [uuid(record.appointmentID), value.rawSpeakerLabel, value.modelID, value.values.count, record.payload])
    }

    static func save(_ record: PatientVoiceProfilePersistenceRecord, in db: Database) throws {
        let value = record.value
        try db.execute(sql: """
            INSERT INTO patient_voice_profiles (id, source_assignment_id, model_id, dimensions, created_at, payload)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(model_id) DO UPDATE SET
                id=excluded.id, source_assignment_id=excluded.source_assignment_id,
                dimensions=excluded.dimensions,
                created_at=excluded.created_at, payload=excluded.payload
            """, arguments: [uuid(value.id), uuid(value.id), value.modelID, value.embedding.count, timestamp(value.createdAt), record.payload])
    }

    static func insert(_ record: SessionDebriefDecisionPersistenceRecord, in db: Database) throws -> Bool {
        let value = record.value
        try db.execute(sql: """
            INSERT INTO session_debrief_decisions
                (id, appointment_id, summary_item_id, kind, target_entity_id, created_at, payload)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(appointment_id, summary_item_id, kind) DO NOTHING
            """, arguments: [uuid(value.id), uuid(value.appointmentID), uuid(value.summaryItemID), value.kind.rawValue, optionalUUID(value.targetEntityID), timestamp(value.createdAt), record.payload])
        return db.changesCount == 1
    }

    static func replaceIndex(
        kind: SearchEntityKind,
        id: UUID,
        title: String,
        body: String,
        date: Date,
        db: Database
    ) throws {
        try index(kind: kind, id: id, title: title, body: body, date: date, db: db)
    }

    static func saveSettings(_ value: VaultSettings, in db: Database) throws {
        let payload = try PersistenceCoding.encode(value)
        try db.execute(sql: "INSERT INTO app_settings (id, use_sample_content, payload) VALUES (1, ?, ?) ON CONFLICT(id) DO UPDATE SET use_sample_content=excluded.use_sample_content, payload=excluded.payload", arguments: [value.useSampleContent, payload])
    }

    private static func insertSQL(table: String, columns: String, updates: String, count: Int, insertOnly: Bool) -> String {
        let values = Array(repeating: "?", count: count).joined(separator: ", ")
        let conflict = insertOnly ? "ON CONFLICT(id) DO NOTHING" : "ON CONFLICT(id) DO UPDATE SET \(updates)"
        return "INSERT INTO \(table) (\(columns)) VALUES (\(values)) \(conflict)"
    }

    private static func index(kind: SearchEntityKind, id entityID: UUID, title: String, body: String, date: Date, db: Database) throws {
        guard try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='care_search'") == 1 else { return }
        try db.execute(sql: "DELETE FROM care_search WHERE kind = ? AND entity_id = ?", arguments: [kind.rawValue, uuid(entityID)])
        try db.execute(sql: "INSERT INTO care_search (kind, entity_id, title, body, occurred_at) VALUES (?, ?, ?, ?, ?)", arguments: [kind.rawValue, uuid(entityID), title, body, String(timestamp(date))])
    }

    private static func uuid(_ value: UUID) -> String { value.uuidString.lowercased() }
    private static func optionalUUID(_ value: UUID?) -> String? { value.map(uuid) }
    private static func timestamp(_ value: Date) -> Double { value.timeIntervalSince1970 }
    private static func optionalTimestamp(_ value: Date?) -> Double? { value.map(timestamp) }
}
