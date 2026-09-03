import Foundation

actor VaultExportService: VaultExporting {
    private enum DeleteState {
        case idle
        case running
        case completed
    }

    private static let maximumRecordsPerKind = 100_000
    private static let maximumDirectoryAttempts = 1_000
    private static let exportPrefix = "Candy Corn export "

    private let store: any CareStore
    private let maintenance: any VaultMaintenance
    private let attachments: any AttachmentStore
    private let logger: any EventLogging
    private let now: @Sendable () -> Date
    private let fileManager: FileManager
    private let temporaryRoot: URL
    private let encoder: JSONEncoder
    private var issuedPackagePaths: Set<String> = []
    private var reservedPackagePaths: Set<String> = []
    private var deleteState = DeleteState.idle

    init(
        store: any CareStore,
        maintenance: any VaultMaintenance,
        attachments: any AttachmentStore,
        logger: any EventLogging,
        now: @escaping @Sendable () -> Date = { Date() },
        fileManager: FileManager = .default,
        temporaryRoot: URL? = nil,
        encoder: JSONEncoder = JSONEncoder()
    ) {
        self.store = store
        self.maintenance = maintenance
        self.attachments = attachments
        self.logger = logger
        self.now = now
        self.fileManager = fileManager
        self.temporaryRoot = (temporaryRoot ?? fileManager.temporaryDirectory).standardizedFileURL
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        self.encoder = encoder
    }

    func makeExport() async throws -> ExportPackage {
        let startedAt = now()
        let createdAt = startedAt
        var stagingURL: URL?
        var reservedPath: String?
        do {
            try validateTemporaryRoot()
            let snapshot = try await store.snapshot()
            try validate(snapshot)
            try Task.checkCancellation()
            try fileManager.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
            let destination = try availablePackageURL(createdAt: createdAt)
            reservedPackagePaths.insert(destination.path)
            reservedPath = destination.path
            let staging = temporaryRoot.appending(path: ".\(UUID().uuidString.lowercased()).partial", directoryHint: .isDirectory)
            stagingURL = staging
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
            try createContentDirectories(in: staging)

            let copiedFiles = try await copyAttachments(snapshot.attachments, into: staging)
            let copied = addingReferenceWarnings(to: copiedFiles, snapshot: snapshot)
            try Task.checkCancellation()
            try writeMarkdown(snapshot: snapshot, copiedPaths: copied.paths, root: staging)
            let manifest = makeManifest(snapshot: snapshot, createdAt: createdAt, copied: copied)
            try writeManifest(manifest, root: staging)
            try Task.checkCancellation()
            try fileManager.moveItem(at: staging, to: destination)
            stagingURL = nil
            reservedPackagePaths.remove(destination.path)
            reservedPath = nil
            issuedPackagePaths.insert(destination.standardizedFileURL.path)
            let count = exportedRecordCount(snapshot)
            logger.record(.exportCompleted, metrics: EventMetrics(durationMilliseconds: elapsed(from: startedAt), count: count))
            return ExportPackage(directoryURL: destination, createdAt: createdAt)
        } catch is CancellationError {
            if let reservedPath { reservedPackagePaths.remove(reservedPath) }
            removeIncomplete(stagingURL: stagingURL)
            throw CancellationError()
        } catch {
            if let reservedPath { reservedPackagePaths.remove(reservedPath) }
            removeIncomplete(stagingURL: stagingURL)
            throw UserFacingError.export
        }
    }

    func cleanup(_ package: ExportPackage) {
        let candidate = package.directoryURL.standardizedFileURL
        guard isDirectChild(candidate, of: temporaryRoot) else { return }
        guard candidate.lastPathComponent.hasPrefix(Self.exportPrefix) else { return }
        guard issuedPackagePaths.remove(candidate.path) != nil else { return }
        guard fileManager.fileExists(atPath: candidate.path) else { return }
        try? fileManager.removeItem(at: candidate)
    }

    func deleteEverything(confirmation: DeleteConfirmation) async throws {
        guard confirmation.accepted else { throw UserFacingError.saving }
        switch deleteState {
        case .completed:
            return
        case .running:
            throw UserFacingError(message: "Your care vault is already being deleted.")
        case .idle:
            deleteState = .running
        }
        do {
            try await maintenance.destroyAndRecreateVault()
            deleteState = .completed
        } catch {
            deleteState = .idle
            throw UserFacingError(message: "Your care vault could not be deleted. Try again.")
        }
    }

    private func validateTemporaryRoot() throws {
        guard temporaryRoot.isFileURL else { throw UserFacingError.export }
        guard temporaryRoot.path != "/", !temporaryRoot.path.isEmpty else { throw UserFacingError.export }
    }

    private func validate(_ snapshot: CareSnapshot) throws {
        let counts = [
            snapshot.journals.count, snapshot.moods.count, snapshot.appointments.count,
            snapshot.goals.count, snapshot.goalProgress.count, snapshot.talkingPoints.count,
            snapshot.artifacts.count, snapshot.attachments.count, snapshot.providers.count,
            snapshot.transcript.count,
        ]
        guard counts.allSatisfy({ $0 >= 0 }) else { throw UserFacingError.export }
        guard counts.allSatisfy({ $0 <= Self.maximumRecordsPerKind }) else { throw UserFacingError.export }
    }

    private func availablePackageURL(createdAt: Date) throws -> URL {
        let baseName = Self.exportPrefix + exportTimestamp(createdAt)
        for attempt in 1...Self.maximumDirectoryAttempts {
            let name = attempt == 1 ? baseName : "\(baseName) \(attempt)"
            let candidate = temporaryRoot.appending(path: name, directoryHint: .isDirectory)
            guard isDirectChild(candidate, of: temporaryRoot) else { throw UserFacingError.export }
            if !fileManager.fileExists(atPath: candidate.path), !reservedPackagePaths.contains(candidate.path) { return candidate }
        }
        throw UserFacingError.export
    }

    private func createContentDirectories(in root: URL) throws {
        let names = ["journals", "appointments", "attachments/audio", "attachments/images", "attachments/documents"]
        guard root.isFileURL, isDirectChild(root, of: temporaryRoot) else { throw UserFacingError.export }
        guard names.count == 5 else { throw UserFacingError.export }
        for name in names.prefix(5) {
            try fileManager.createDirectory(at: root.appending(path: name, directoryHint: .isDirectory), withIntermediateDirectories: true)
        }
    }

    private func copyAttachments(_ values: [Attachment], into root: URL) async throws -> CopiedAttachments {
        var paths: [UUID: String] = [:]
        var warnings: [ExportWarning] = []
        for attachment in sortedAttachments(values).prefix(Self.maximumRecordsPerKind) {
            try Task.checkCancellation()
            do {
                let relativePath = try await copyAttachment(attachment, into: root)
                paths[attachment.id] = relativePath
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                warnings.append(ExportWarning(
                    code: .attachmentUnavailable,
                    attachmentID: attachment.id,
                    message: "The attachment was unavailable and was not copied."
                ))
            }
        }
        return CopiedAttachments(paths: paths, warnings: warnings)
    }

    private func copyAttachment(_ attachment: Attachment, into root: URL) async throws -> String {
        let directoryName = attachmentDirectory(attachment.kind)
        let exportName = attachment.id.uuidString.lowercased() + "." + attachmentExtension(attachment)
        let relativePath = "attachments/\(directoryName)/\(exportName)"
        let finalURL = root.appending(path: relativePath)
        let staging = root.appending(path: ".attachment-\(attachment.id.uuidString.lowercased())", directoryHint: .isDirectory)
        guard isContained(finalURL, by: root), isContained(staging, by: root) else { throw UserFacingError.export }
        guard !fileManager.fileExists(atPath: finalURL.path) else { throw UserFacingError.export }
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: staging) }
        try await attachments.copyIntoExport(attachment, destination: staging)
        try Task.checkCancellation()
        let copiedFiles = try fileManager.contentsOfDirectory(at: staging, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        guard copiedFiles.count == 1, let source = copiedFiles.first else { throw UserFacingError.export }
        guard try source.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw UserFacingError.export }
        try fileManager.moveItem(at: source, to: finalURL)
        return relativePath
    }

    private func addingReferenceWarnings(to copied: CopiedAttachments, snapshot: CareSnapshot) -> CopiedAttachments {
        let inventoryIDs = Set(snapshot.attachments.map(\.id))
        var referencedIDs = Set<UUID>()
        for journal in snapshot.journals.prefix(Self.maximumRecordsPerKind) {
            if let id = journal.originalAttachmentID { referencedIDs.insert(id) }
            if let id = journal.audioAttachmentID { referencedIDs.insert(id) }
        }
        for appointment in snapshot.appointments.prefix(Self.maximumRecordsPerKind) {
            if let id = appointment.recordingAttachmentID { referencedIDs.insert(id) }
        }
        let existingWarnings = Set(copied.warnings.map(\.attachmentID))
        let missing = referencedIDs.subtracting(inventoryIDs).subtracting(existingWarnings)
        let warnings = missing.map {
            ExportWarning(code: .attachmentUnavailable, attachmentID: $0, message: "The attachment was unavailable and was not copied.")
        }
        return CopiedAttachments(paths: copied.paths, warnings: copied.warnings + warnings)
    }

    private func writeMarkdown(snapshot: CareSnapshot, copiedPaths: [UUID: String], root: URL) throws {
        for journal in sortedJournals(snapshot.journals).prefix(Self.maximumRecordsPerKind) {
            try Task.checkCancellation()
            let relativePath = journalMarkdownPath(journal)
            try write(journalMarkdown(journal, copiedPaths: copiedPaths), to: root.appending(path: relativePath))
        }
        for appointment in sortedAppointments(snapshot.appointments).prefix(Self.maximumRecordsPerKind) {
            try Task.checkCancellation()
            let relativePath = appointmentMarkdownPath(appointment)
            try write(appointmentMarkdown(appointment, copiedPaths: copiedPaths), to: root.appending(path: relativePath))
        }
        try write(moodMarkdown(snapshot.moods), to: root.appending(path: "mood.md"))
        try write(goalsMarkdown(snapshot.goals, progress: snapshot.goalProgress), to: root.appending(path: "goals.md"))
        try write(talkingPointsMarkdown(snapshot.talkingPoints), to: root.appending(path: "talking-points.md"))
        try write(providersMarkdown(snapshot.providers), to: root.appending(path: "providers.md"))
    }

    private func writeManifest(_ manifest: ExportManifest, root: URL) throws {
        let data = try encoder.encode(manifest)
        guard !data.isEmpty, isContained(root.appending(path: "index.json"), by: root) else { throw UserFacingError.export }
        try data.write(to: root.appending(path: "index.json"), options: .atomic)
    }

    private func write(_ value: String, to url: URL) throws {
        guard url.isFileURL, !value.isEmpty else { throw UserFacingError.export }
        guard let data = value.data(using: .utf8), !data.isEmpty else { throw UserFacingError.export }
        try data.write(to: url, options: .atomic)
    }

    private func makeManifest(snapshot: CareSnapshot, createdAt: Date, copied: CopiedAttachments) -> ExportManifest {
        ExportManifest(
            version: ExportManifest.currentVersion,
            createdAt: createdAt,
            journals: sortedJournals(snapshot.journals).map { journal in
                ExportJournal(
                    id: journal.id, createdAt: journal.createdAt, updatedAt: journal.updatedAt,
                    inputType: journal.inputType, title: journal.title, rawText: journal.rawText,
                    cleanedText: journal.cleanedText, summaryItems: journal.summaryItems,
                    originalAttachmentID: journal.originalAttachmentID, audioAttachmentID: journal.audioAttachmentID,
                    moodLogID: journal.moodLogID, pinnedForNextAppointment: journal.pinnedForNextAppointment,
                    processingStatus: journal.processingStatus, provenance: journal.provenance,
                    markdownPath: journalMarkdownPath(journal), attachmentPaths: journalAttachmentPaths(journal, copiedPaths: copied.paths)
                )
            },
            moods: sortedMoods(snapshot.moods).map {
                ExportMood(id: $0.id, createdAt: $0.createdAt, mood: $0.mood, anxiety: $0.anxiety, energy: $0.energy, customValues: $0.customValues, note: $0.note, markdownPath: "mood.md")
            },
            appointments: sortedAppointments(snapshot.appointments).map {
                ExportAppointment(
                    id: $0.id, kind: $0.kind, scheduledAt: $0.scheduledAt, startedAt: $0.startedAt,
                    endedAt: $0.endedAt, providerID: $0.providerID, providerName: $0.providerName,
                    recordingAttachmentID: $0.recordingAttachmentID, transcriptID: $0.transcriptID,
                    summaryID: $0.summaryID, status: $0.status, manualNotes: $0.manualNotes,
                    markdownPath: appointmentMarkdownPath($0), recordingPath: $0.recordingAttachmentID.flatMap { copied.paths[$0] }
                )
            },
            goals: sortedGoals(snapshot.goals).map {
                ExportGoal(id: $0.id, title: $0.title, detail: $0.detail, cadence: $0.cadence, source: $0.source, sourceEntityID: $0.sourceEntityID, sourceTimestampMilliseconds: $0.sourceTimestampMilliseconds, status: $0.status, createdAt: $0.createdAt, targetDate: $0.targetDate, provenance: $0.provenance, markdownPath: "goals.md")
            },
            goalProgress: sortedProgress(snapshot.goalProgress).map {
                ExportGoalProgress(id: $0.id, goalID: $0.goalID, sourceEntryID: $0.sourceEntryID, note: $0.note, source: $0.source, createdAt: $0.createdAt, markdownPath: "goals.md")
            },
            talkingPoints: sortedTalkingPoints(snapshot.talkingPoints).map {
                ExportTalkingPoint(id: $0.id, text: $0.text, source: $0.source, sourceID: $0.sourceID, targetAppointmentKind: $0.targetAppointmentKind, isImportant: $0.isImportant, status: $0.status, createdAt: $0.createdAt, provenance: $0.provenance, markdownPath: "talking-points.md")
            },
            artifacts: sortedArtifacts(snapshot.artifacts).map {
                ExportArtifact(id: $0.id, kind: $0.kind, sourceIDs: $0.sourceIDs, provider: $0.provider, model: $0.model, structuredPayload: $0.structuredPayload, createdAt: $0.createdAt, exportPath: "index.json")
            },
            attachments: sortedAttachments(snapshot.attachments).map {
                ExportAttachment(id: $0.id, kind: $0.kind, mediaType: $0.mediaType, byteCount: $0.byteCount, durationMilliseconds: $0.durationMilliseconds, createdAt: $0.createdAt, isSample: $0.isSample, exportPath: copied.paths[$0.id])
            },
            providers: sortedProviders(snapshot.providers).map {
                ExportProvider(id: $0.id, name: $0.name, appointmentKind: $0.appointmentKind, isSample: $0.isSample, markdownPath: "providers.md")
            },
            transcripts: sortedTranscripts(snapshot.transcript).map {
                ExportTranscript(id: $0.id, appointmentID: $0.appointmentID, speaker: $0.speaker, rawSpeakerLabel: $0.rawSpeakerLabel, startMilliseconds: $0.startMilliseconds, endMilliseconds: $0.endMilliseconds, text: $0.text, confidence: $0.confidence, exportPath: "index.json")
            },
            settings: snapshot.settings,
            warnings: copied.warnings.sorted { $0.attachmentID.uuidString < $1.attachmentID.uuidString }
        )
    }

    private func journalMarkdown(_ journal: JournalEntry, copiedPaths: [UUID: String]) -> String {
        var lines = [
            "# \(singleLine(journal.title, fallback: "Journal entry"))", "",
            "- ID: `\(journal.id.uuidString.lowercased())`",
            "- Created: \(isoDate(journal.createdAt))", "- Updated: \(isoDate(journal.updatedAt))",
            "- Input type: \(journal.inputType.rawValue)", "- Provenance: \(singleLine(journal.provenance.label, fallback: "Not recorded"))",
            "- Provenance detail: \(singleLine(journal.provenance.detail, fallback: "Not recorded"))", "",
            "## Original", "", journal.rawText, "",
        ]
        if let cleaned = journal.cleanedText {
            lines.append(contentsOf: ["## Cleaned text", "", cleaned, ""])
        }
        if !journal.summaryItems.isEmpty {
            lines.append(contentsOf: ["## Summary", ""])
            lines.append(contentsOf: journal.summaryItems.prefix(Self.maximumRecordsPerKind).map { "- \($0)" })
            lines.append("")
        }
        let paths = journalAttachmentPaths(journal, copiedPaths: copiedPaths)
        if !paths.isEmpty {
            lines.append(contentsOf: ["## Attachments", ""])
            lines.append(contentsOf: paths.map { "- [Saved attachment](../\($0))" })
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func appointmentMarkdown(_ appointment: Appointment, copiedPaths: [UUID: String]) -> String {
        let title = "\(appointment.kind.rawValue.capitalized) appointment"
        var lines = [
            "# \(title)", "", "- ID: `\(appointment.id.uuidString.lowercased())`",
            "- Kind: \(appointment.kind.rawValue)", "- Status: \(appointment.status.rawValue)",
            "- Scheduled: \(optionalDate(appointment.scheduledAt))", "- Started: \(optionalDate(appointment.startedAt))",
            "- Ended: \(optionalDate(appointment.endedAt))", "- Duration: \(appointmentDuration(appointment))",
            "- Provider: \(singleLine(appointment.providerName, fallback: "Not recorded"))", "",
            "## Manual notes", "", appointment.manualNotes, "",
        ]
        if let id = appointment.recordingAttachmentID, let path = copiedPaths[id] {
            lines.append(contentsOf: ["## Recording", "", "[Saved recording](../\(path))", ""])
        }
        return lines.joined(separator: "\n")
    }

    private func moodMarkdown(_ moods: [MoodLog]) -> String {
        var lines = ["# Mood logs", "", "| Date | Mood | Anxiety | Energy | Custom values | Note |", "| --- | ---: | ---: | ---: | --- | --- |"]
        for mood in sortedMoods(moods).prefix(Self.maximumRecordsPerKind) {
            let custom = mood.customValues.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            lines.append("| \(isoDate(mood.createdAt)) | \(number(mood.mood)) | \(number(mood.anxiety)) | \(number(mood.energy)) | \(tableCell(custom)) | \(tableCell(mood.note ?? "")) |")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func goalsMarkdown(_ goals: [Goal], progress: [GoalProgress]) -> String {
        var lines = ["# Goals", ""]
        let groupedProgress = Dictionary(grouping: sortedProgress(progress), by: \GoalProgress.goalID)
        for goal in sortedGoals(goals).prefix(Self.maximumRecordsPerKind) {
            lines.append(contentsOf: [
                "## \(singleLine(goal.title, fallback: "Untitled goal"))", "",
                "- ID: `\(goal.id.uuidString.lowercased())`", "- Status: \(goal.status.rawValue)",
                "- Cadence: \(goal.cadence.rawValue)", "- Source: \(goal.source.rawValue)",
                "- Created: \(isoDate(goal.createdAt))", "- Target: \(optionalDate(goal.targetDate))",
                "- Provenance: \(singleLine(goal.provenance.label, fallback: "Not recorded"))", "",
            ])
            if let detail = goal.detail { lines.append(contentsOf: [detail, ""]) }
            let updates = groupedProgress[goal.id] ?? []
            if !updates.isEmpty {
                lines.append(contentsOf: ["### Progress", ""])
                for update in updates.prefix(Self.maximumRecordsPerKind) {
                    lines.append("- \(isoDate(update.createdAt)), \(update.source.rawValue): \(singleLine(update.note, fallback: "No note"))")
                }
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func talkingPointsMarkdown(_ points: [TalkingPoint]) -> String {
        var lines = ["# Bring up next time", ""]
        for point in sortedTalkingPoints(points).prefix(Self.maximumRecordsPerKind) {
            lines.append(contentsOf: [
                "## \(singleLine(point.text, fallback: "Talking point"))", "",
                "- ID: `\(point.id.uuidString.lowercased())`", "- Status: \(point.status.rawValue)",
                "- Source: \(point.source.rawValue)", "- Created: \(isoDate(point.createdAt))",
                "- Important: \(point.isImportant ? "Yes" : "No")",
                "- Appointment kind: \(point.targetAppointmentKind?.rawValue ?? "Any")",
                "- Provenance: \(singleLine(point.provenance.label, fallback: "Not recorded"))", "",
            ])
        }
        return lines.joined(separator: "\n")
    }

    private func providersMarkdown(_ providers: [ProviderProfile]) -> String {
        var lines = ["# Providers", "", "| Name | Appointment kind | ID |", "| --- | --- | --- |"]
        for provider in sortedProviders(providers).prefix(Self.maximumRecordsPerKind) {
            lines.append("| \(tableCell(provider.name)) | \(provider.appointmentKind.rawValue) | `\(provider.id.uuidString.lowercased())` |")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func journalAttachmentPaths(_ journal: JournalEntry, copiedPaths: [UUID: String]) -> [String] {
        [journal.originalAttachmentID, journal.audioAttachmentID]
            .compactMap { $0 }
            .reduce(into: [UUID]()) { ids, id in if !ids.contains(id) { ids.append(id) } }
            .compactMap { copiedPaths[$0] }
    }

    private func journalMarkdownPath(_ journal: JournalEntry) -> String {
        "journals/\(day(journal.createdAt))-\(safeSlug(journal.title, fallback: "journal"))-\(journal.id.uuidString.lowercased()).md"
    }

    private func appointmentMarkdownPath(_ appointment: Appointment) -> String {
        let date = appointment.startedAt ?? appointment.scheduledAt ?? appointment.endedAt ?? .distantPast
        return "appointments/\(day(date))-\(safeSlug(appointment.kind.rawValue, fallback: "appointment"))-\(appointment.id.uuidString.lowercased()).md"
    }

    private func safeSlug(_ value: String, fallback: String) -> String {
        let folded = value.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX")).lowercased()
        var result = ""
        var needsSeparator = false
        for scalar in folded.unicodeScalars.prefix(512) {
            if CharacterSet.alphanumerics.contains(scalar), scalar.isASCII {
                if needsSeparator, !result.isEmpty { result.append("-") }
                result.unicodeScalars.append(scalar)
                needsSeparator = false
            } else {
                needsSeparator = true
            }
            if result.count >= 48 { break }
        }
        let bounded = String(result.prefix(48)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return bounded.isEmpty ? fallback : bounded
    }

    private func singleLine(_ value: String, fallback: String) -> String {
        let compact = value.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        return compact.isEmpty ? fallback : compact
    }

    private func tableCell(_ value: String) -> String {
        value.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: "<br>")
    }

    private func attachmentDirectory(_ kind: AttachmentKind) -> String {
        switch kind {
        case .audio: "audio"
        case .image: "images"
        case .document: "documents"
        }
    }

    private func attachmentExtension(_ attachment: Attachment) -> String {
        switch attachment.mediaType.lowercased() {
        case "audio/mp4", "audio/x-m4a": "m4a"
        case "audio/aac": "aac"
        case "image/jpeg": "jpg"
        case "image/png": "png"
        case "image/heic", "image/heif": "heic"
        case "application/pdf": "pdf"
        case "text/plain": "txt"
        case "text/markdown": "md"
        case "application/json": "json"
        default:
            switch attachment.kind {
            case .audio: "m4a"
            case .image: "jpg"
            case .document: "bin"
            }
        }
    }

    private func appointmentDuration(_ appointment: Appointment) -> String {
        guard let start = appointment.startedAt, let end = appointment.endedAt, end >= start else { return "Not recorded" }
        return "\(Int(end.timeIntervalSince(start))) seconds"
    }

    private func number(_ value: Int?) -> String { value.map(String.init) ?? "" }
    private func optionalDate(_ value: Date?) -> String { value.map(isoDate) ?? "Not recorded" }
    private func day(_ date: Date) -> String { String(isoDate(date).prefix(10)) }

    private func isoDate(_ date: Date) -> String {
        Date.ISO8601FormatStyle(includingFractionalSeconds: false).format(date)
    }

    private func exportTimestamp(_ date: Date) -> String {
        isoDate(date).replacingOccurrences(of: ":", with: "-")
    }

    private func elapsed(from start: Date) -> Int {
        max(0, Int(now().timeIntervalSince(start) * 1_000))
    }

    private func exportedRecordCount(_ snapshot: CareSnapshot) -> Int {
        snapshot.journals.count + snapshot.moods.count + snapshot.appointments.count + snapshot.goals.count
            + snapshot.goalProgress.count + snapshot.talkingPoints.count + snapshot.artifacts.count
            + snapshot.attachments.count + snapshot.providers.count + snapshot.transcript.count
    }

    private func removeIncomplete(stagingURL: URL?) {
        for url in [stagingURL].compactMap({ $0 }).prefix(1) where isDirectChild(url, of: temporaryRoot) {
            if fileManager.fileExists(atPath: url.path) { try? fileManager.removeItem(at: url) }
        }
    }

    private func isDirectChild(_ candidate: URL, of root: URL) -> Bool {
        candidate.standardizedFileURL.deletingLastPathComponent().path == root.standardizedFileURL.path
    }

    private func isContained(_ candidate: URL, by root: URL) -> Bool {
        let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
        let candidatePath = candidate.resolvingSymlinksInPath().standardizedFileURL.path
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }

    private func sortedJournals(_ values: [JournalEntry]) -> [JournalEntry] { values.sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) } }
    private func sortedMoods(_ values: [MoodLog]) -> [MoodLog] { values.sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) } }
    private func sortedAppointments(_ values: [Appointment]) -> [Appointment] { values.sorted { (($0.startedAt ?? $0.scheduledAt ?? .distantPast), $0.id.uuidString) < (($1.startedAt ?? $1.scheduledAt ?? .distantPast), $1.id.uuidString) } }
    private func sortedGoals(_ values: [Goal]) -> [Goal] { values.sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) } }
    private func sortedProgress(_ values: [GoalProgress]) -> [GoalProgress] { values.sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) } }
    private func sortedTalkingPoints(_ values: [TalkingPoint]) -> [TalkingPoint] { values.sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) } }
    private func sortedArtifacts(_ values: [AIArtifact]) -> [AIArtifact] { values.sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) } }
    private func sortedAttachments(_ values: [Attachment]) -> [Attachment] { values.sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) } }
    private func sortedProviders(_ values: [ProviderProfile]) -> [ProviderProfile] { values.sorted { ($0.name, $0.id.uuidString) < ($1.name, $1.id.uuidString) } }
    private func sortedTranscripts(_ values: [TranscriptSegment]) -> [TranscriptSegment] { values.sorted { ($0.appointmentID.uuidString, $0.startMilliseconds, $0.id.uuidString) < ($1.appointmentID.uuidString, $1.startMilliseconds, $1.id.uuidString) } }
}

private struct CopiedAttachments: Sendable {
    let paths: [UUID: String]
    let warnings: [ExportWarning]
}
