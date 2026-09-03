import GRDB

enum SampleContentSeeder {
    static func prepareIfNeeded(in db: Database) throws {
        let settingsCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM app_settings WHERE id = 1") ?? 0
        guard settingsCount == 0 else { return }
        let defaults = VaultSettings(useSampleContent: true, audioRetention: .ask, aiMode: .off, aiProvider: .off)
        try VaultRecordWriter.saveSettings(defaults, in: db)
        try seed(in: db)
    }

    static func seed(in db: Database) throws {
        for provider in SeededData.providers {
            try VaultRecordWriter.save(try ProviderPersistenceRecord(provider), in: db, insertOnly: true)
        }
        for attachment in SeededData.attachments {
            try VaultRecordWriter.save(try AttachmentPersistenceRecord(attachment), in: db, insertOnly: true)
        }
        for mood in SeededData.moodLogs {
            try VaultRecordWriter.save(try MoodPersistenceRecord(mood, isSample: true), in: db, insertOnly: true)
        }
        for appointment in SeededData.appointments {
            try VaultRecordWriter.save(try AppointmentPersistenceRecord(appointment, isSample: true), in: db, insertOnly: true)
        }
        for journal in SeededData.journalEntries {
            try VaultRecordWriter.save(try JournalPersistenceRecord(journal, isSample: true), in: db, insertOnly: true)
        }
        for goal in SeededData.goals {
            try VaultRecordWriter.save(try GoalPersistenceRecord(goal, isSample: true), in: db, insertOnly: true)
        }
        for point in SeededData.talkingPoints {
            try VaultRecordWriter.save(try TalkingPointPersistenceRecord(point, isSample: true), in: db, insertOnly: true)
        }
        for artifact in SeededData.aiArtifacts {
            try VaultRecordWriter.save(try ArtifactPersistenceRecord(artifact, isSample: true), in: db, insertOnly: true)
        }
        for segment in SeededData.transcript {
            try VaultRecordWriter.save(try TranscriptPersistenceRecord(segment, isSample: true), in: db, insertOnly: true)
        }
    }

    static func remove(in db: Database) throws {
        if try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='care_search'") == 1 {
            try db.execute(sql: "DELETE FROM care_search WHERE (kind, entity_id) IN (SELECT 'journal', id FROM journal_entries WHERE is_sample = 1)")
            try db.execute(sql: "DELETE FROM care_search WHERE (kind, entity_id) IN (SELECT 'goal', id FROM goals WHERE is_sample = 1)")
            try db.execute(sql: "DELETE FROM care_search WHERE (kind, entity_id) IN (SELECT 'talkingPoint', id FROM talking_points WHERE is_sample = 1)")
        }
        try db.execute(sql: "DELETE FROM transcript_segments WHERE is_sample = 1")
        try db.execute(sql: "DELETE FROM goal_progress WHERE is_sample = 1")
        try db.execute(sql: "DELETE FROM ai_artifacts WHERE is_sample = 1")
        try db.execute(sql: "DELETE FROM talking_points WHERE is_sample = 1")
        try db.execute(sql: "DELETE FROM goals WHERE is_sample = 1")
        try db.execute(sql: "DELETE FROM journal_entries WHERE is_sample = 1")
        try db.execute(sql: "DELETE FROM appointments WHERE is_sample = 1")
        try db.execute(sql: "DELETE FROM mood_logs WHERE is_sample = 1")
        try db.execute(sql: "DELETE FROM attachments WHERE is_sample = 1")
        try db.execute(sql: "DELETE FROM providers WHERE is_sample = 1")
    }
}
