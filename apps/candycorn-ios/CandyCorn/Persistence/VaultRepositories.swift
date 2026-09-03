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
                settings: try Self.fetchSettings(db)
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

    func search(_ query: String, limit: Int) async throws -> [SearchHit] {
        let normalized = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        guard !normalized.isEmpty, (1...100).contains(limit) else { throw VaultRepositoryError.invalidInput }
        let terms = Self.searchTerms(normalized)
        guard !terms.isEmpty else { return [] }
        let hits = try await database.read { db in
            if try Self.hasSearchTable(db) {
                do { return try Self.ftsSearch(terms: terms, limit: limit, db: db) } catch { }
            }
            return try Self.likeSearch(query: normalized, limit: limit, db: db)
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
        return parts.prefix(20).map(String.init).filter { $0.count > 1 && !operators.contains($0.lowercased()) }
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

    private static func likeSearch(query: String, limit: Int, db: Database) throws -> [SearchHit] {
        let escaped = query.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        let pattern = "%\(escaped)%"
        let rows = try Row.fetchAll(db, sql: """
            SELECT 'journal' kind, id entity_id, title, raw_text body, created_at occurred_at
              FROM journal_entries WHERE title LIKE ? ESCAPE '\\' COLLATE NOCASE OR raw_text LIKE ? ESCAPE '\\' COLLATE NOCASE OR cleaned_text LIKE ? ESCAPE '\\' COLLATE NOCASE OR summary_text LIKE ? ESCAPE '\\' COLLATE NOCASE
            UNION ALL
            SELECT 'goal', id, title, COALESCE(detail, title), created_at
              FROM goals WHERE title LIKE ? ESCAPE '\\' COLLATE NOCASE OR detail LIKE ? ESCAPE '\\' COLLATE NOCASE
            UNION ALL
            SELECT 'talkingPoint', id, 'Bring up next time', text, created_at
              FROM talking_points WHERE text LIKE ? ESCAPE '\\' COLLATE NOCASE
            UNION ALL
            SELECT 'appointment', id, 'Appointment', manual_notes, COALESCE(started_at, scheduled_at, 0)
              FROM appointments WHERE manual_notes LIKE ? ESCAPE '\\' COLLATE NOCASE
            UNION ALL
            SELECT 'mood', id, 'Mood check-in', COALESCE(note, ''), created_at
              FROM mood_logs WHERE note LIKE ? ESCAPE '\\' COLLATE NOCASE
            ORDER BY occurred_at DESC, entity_id ASC LIMIT ?
            """, arguments: [pattern, pattern, pattern, pattern, pattern, pattern, pattern, pattern, pattern, limit])
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
        try index(kind: .goal, id: value.id, title: value.title, body: value.detail ?? value.title, date: value.createdAt, db: db)
    }

    static func save(_ record: GoalProgressPersistenceRecord, in db: Database, insertOnly: Bool = false) throws {
        let value = record.value
        try db.execute(sql: insertSQL(table: "goal_progress", columns: "id, goal_id, source_entry_id, created_at, is_sample, payload", updates: "goal_id=excluded.goal_id, source_entry_id=excluded.source_entry_id, created_at=excluded.created_at, payload=excluded.payload", count: 6, insertOnly: insertOnly), arguments: [uuid(value.id), uuid(value.goalID), optionalUUID(value.sourceEntryID), timestamp(value.createdAt), record.isSample, record.payload])
    }

    static func save(_ record: TalkingPointPersistenceRecord, in db: Database, insertOnly: Bool = false) throws {
        let value = record.value
        try db.execute(sql: insertSQL(table: "talking_points", columns: "id, created_at, text, status, source_id, is_sample, payload", updates: "created_at=excluded.created_at, text=excluded.text, status=excluded.status, source_id=excluded.source_id, payload=excluded.payload", count: 7, insertOnly: insertOnly), arguments: [uuid(value.id), timestamp(value.createdAt), value.text, value.status.rawValue, optionalUUID(value.sourceID), record.isSample, record.payload])
        try index(kind: .talkingPoint, id: value.id, title: "Bring up next time", body: value.text, date: value.createdAt, db: db)
    }

    static func save(_ record: ArtifactPersistenceRecord, in db: Database, insertOnly: Bool = false) throws {
        let value = record.value
        try db.execute(sql: insertSQL(table: "ai_artifacts", columns: "id, kind, provider, model, created_at, is_sample, payload", updates: "kind=excluded.kind, provider=excluded.provider, model=excluded.model, created_at=excluded.created_at, payload=excluded.payload", count: 7, insertOnly: insertOnly), arguments: [uuid(value.id), value.kind.rawValue, value.provider, value.model, timestamp(value.createdAt), record.isSample, record.payload])
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
