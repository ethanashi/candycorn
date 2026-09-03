import GRDB

enum VaultMigrations {
    static let latestIdentifier = "v3_search"

    static func makeMigrator(includeSearch: Bool = true, forcedFailure: Bool = false) -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_core") { db in
            try createCoreTables(db)
        }
        migrator.registerMigration("v2_relations") { db in
            try createRelationTables(db)
            try createIndexes(db)
        }
        migrator.registerMigration(latestIdentifier) { db in
            if forcedFailure {
                try db.execute(sql: "CREATE TABLE forced_rollback_marker (id INTEGER PRIMARY KEY)")
                throw VaultMigrationError.forcedFailure
            }
            guard includeSearch else { return }
            try db.execute(sql: """
                CREATE VIRTUAL TABLE IF NOT EXISTS care_search USING fts5(
                    kind UNINDEXED,
                    entity_id UNINDEXED,
                    title,
                    body,
                    occurred_at UNINDEXED,
                    tokenize = 'unicode61 remove_diacritics 2'
                )
                """)
        }
        return migrator
    }

    private static func createCoreTables(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE providers (
                id TEXT PRIMARY KEY NOT NULL,
                name TEXT NOT NULL,
                appointment_kind TEXT NOT NULL,
                is_sample INTEGER NOT NULL DEFAULT 0 CHECK (is_sample IN (0, 1)),
                payload BLOB NOT NULL
            );
            CREATE TABLE attachments (
                id TEXT PRIMARY KEY NOT NULL,
                kind TEXT NOT NULL,
                relative_path TEXT NOT NULL UNIQUE,
                media_type TEXT NOT NULL,
                byte_count INTEGER NOT NULL CHECK (byte_count >= 0),
                duration_milliseconds INTEGER,
                created_at REAL NOT NULL,
                is_sample INTEGER NOT NULL DEFAULT 0 CHECK (is_sample IN (0, 1)),
                payload BLOB NOT NULL
            );
            CREATE TABLE mood_logs (
                id TEXT PRIMARY KEY NOT NULL,
                created_at REAL NOT NULL,
                note TEXT,
                is_sample INTEGER NOT NULL DEFAULT 0 CHECK (is_sample IN (0, 1)),
                payload BLOB NOT NULL
            );
            CREATE TABLE appointments (
                id TEXT PRIMARY KEY NOT NULL,
                provider_id TEXT REFERENCES providers(id) ON DELETE SET NULL,
                scheduled_at REAL,
                started_at REAL,
                ended_at REAL,
                status TEXT NOT NULL,
                manual_notes TEXT NOT NULL DEFAULT '',
                is_sample INTEGER NOT NULL DEFAULT 0 CHECK (is_sample IN (0, 1)),
                payload BLOB NOT NULL
            );
            CREATE TABLE journal_entries (
                id TEXT PRIMARY KEY NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                title TEXT NOT NULL,
                raw_text TEXT NOT NULL,
                cleaned_text TEXT,
                summary_text TEXT NOT NULL,
                original_attachment_id TEXT REFERENCES attachments(id) ON DELETE SET NULL,
                audio_attachment_id TEXT REFERENCES attachments(id) ON DELETE SET NULL,
                mood_log_id TEXT REFERENCES mood_logs(id) ON DELETE SET NULL,
                is_sample INTEGER NOT NULL DEFAULT 0 CHECK (is_sample IN (0, 1)),
                payload BLOB NOT NULL
            );
            CREATE TABLE goals (
                id TEXT PRIMARY KEY NOT NULL,
                created_at REAL NOT NULL,
                title TEXT NOT NULL,
                detail TEXT,
                status TEXT NOT NULL,
                source_entity_id TEXT,
                is_sample INTEGER NOT NULL DEFAULT 0 CHECK (is_sample IN (0, 1)),
                payload BLOB NOT NULL
            );
            CREATE TABLE talking_points (
                id TEXT PRIMARY KEY NOT NULL,
                created_at REAL NOT NULL,
                text TEXT NOT NULL,
                status TEXT NOT NULL,
                source_id TEXT,
                is_sample INTEGER NOT NULL DEFAULT 0 CHECK (is_sample IN (0, 1)),
                payload BLOB NOT NULL
            );
            CREATE TABLE ai_artifacts (
                id TEXT PRIMARY KEY NOT NULL,
                kind TEXT NOT NULL,
                provider TEXT NOT NULL,
                model TEXT NOT NULL,
                created_at REAL NOT NULL,
                is_sample INTEGER NOT NULL DEFAULT 0 CHECK (is_sample IN (0, 1)),
                payload BLOB NOT NULL
            );
            CREATE TABLE app_settings (
                id INTEGER PRIMARY KEY NOT NULL CHECK (id = 1),
                use_sample_content INTEGER NOT NULL CHECK (use_sample_content IN (0, 1)),
                payload BLOB NOT NULL
            );
            """)
    }

    private static func createRelationTables(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE goal_progress (
                id TEXT PRIMARY KEY NOT NULL,
                goal_id TEXT NOT NULL REFERENCES goals(id) ON DELETE CASCADE,
                source_entry_id TEXT REFERENCES journal_entries(id) ON DELETE SET NULL,
                created_at REAL NOT NULL,
                is_sample INTEGER NOT NULL DEFAULT 0 CHECK (is_sample IN (0, 1)),
                payload BLOB NOT NULL
            );
            CREATE TABLE transcript_segments (
                id TEXT PRIMARY KEY NOT NULL,
                appointment_id TEXT NOT NULL REFERENCES appointments(id) ON DELETE CASCADE,
                start_milliseconds INTEGER NOT NULL CHECK (start_milliseconds >= 0),
                end_milliseconds INTEGER NOT NULL CHECK (end_milliseconds > start_milliseconds),
                is_sample INTEGER NOT NULL DEFAULT 0 CHECK (is_sample IN (0, 1)),
                payload BLOB NOT NULL
            );
            CREATE TABLE ai_artifact_sources (
                artifact_id TEXT NOT NULL REFERENCES ai_artifacts(id) ON DELETE CASCADE,
                source_id TEXT NOT NULL,
                position INTEGER NOT NULL CHECK (position >= 0),
                PRIMARY KEY (artifact_id, position)
            );
            """)
    }

    private static func createIndexes(_ db: Database) throws {
        try db.execute(sql: """
            CREATE INDEX journal_entries_created_at ON journal_entries(created_at DESC, id);
            CREATE INDEX mood_logs_created_at ON mood_logs(created_at DESC, id);
            CREATE INDEX appointments_scheduled_at ON appointments(scheduled_at DESC, id);
            CREATE INDEX goals_created_at ON goals(created_at DESC, id);
            CREATE INDEX talking_points_created_at ON talking_points(created_at DESC, id);
            CREATE INDEX transcript_segments_appointment ON transcript_segments(appointment_id, start_milliseconds, id);
            CREATE INDEX attachments_sample ON attachments(is_sample);
            """)
    }
}

enum VaultMigrationError: Error, Equatable, Sendable {
    case forcedFailure
}
