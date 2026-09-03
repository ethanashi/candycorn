import Foundation
import Testing
@testable import CandyCorn

@Suite("Weekly consolidation")
struct WeeklyConsolidatorTests {
    private static let now = date(2026, 3, 11, 12)
    private static let journalID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private static let goalID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!

    @Test("Calendar weeks honor the injected first weekday and daylight-saving boundary")
    func calendarBoundaries() throws {
        var monday = Self.calendar(firstWeekday: 2)
        let interval = try WeeklyConsolidator.weekInterval(
            containing: Self.date(2026, 3, 8, 12), calendar: monday
        )
        #expect(monday.component(.weekday, from: interval.start) == 2)
        #expect(interval.duration == 167 * 60 * 60)

        monday.firstWeekday = 1
        let sunday = try WeeklyConsolidator.weekInterval(containing: Self.now, calendar: monday)
        #expect(monday.component(.weekday, from: sunday.start) == 1)
        #expect(sunday.start != interval.start)

        let yearBoundary = try WeeklyConsolidator.weekInterval(
            containing: Self.date(2027, 1, 1, 12), calendar: Self.calendar(firstWeekday: 2)
        )
        #expect(Self.calendar(firstWeekday: 2).component(.year, from: yearBoundary.start) == 2026)
        #expect(Self.calendar(firstWeekday: 2).component(.year, from: yearBoundary.end) == 2027)
    }

    @Test("Source selection is canonical, bounded, and keeps older open items")
    func sourceSelectionAndCaps() throws {
        var snapshot = Self.snapshot()
        snapshot.moods = [MoodLog(
            id: UUID(uuidString: "30000000-0000-0000-0000-000000000001")!,
            createdAt: Self.now.addingTimeInterval(-60), mood: 6, anxiety: 4, energy: 5,
            customValues: [:], note: "Steady morning"
        )]
        snapshot.talkingPoints = [Self.talkingPoint(createdAt: Self.now.addingTimeInterval(-30 * 24 * 60 * 60))]
        let preparation = try #require(try WeeklyConsolidator.makePreparation(
            snapshot: snapshot, for: Self.now, calendar: Self.calendar()
        ))

        #expect(preparation.input.sources.map(\.document.kind) == [.journal, .moodTrend, .talkingPoint, .goal])
        #expect(preparation.input.sources.map(\.id).contains(Self.goalID))
        #expect(preparation.input.requestText.count <= WeeklyConsolidator.maximumRequestCharacters)
        #expect(preparation.input.sources.allSatisfy {
            $0.document.text.count <= WeeklyConsolidator.maximumSourceCharacters
        })

        var crowded = Self.snapshot()
        crowded.goals = []
        crowded.journals = (0..<60).map { index in
            Self.journal(id: Self.uuid(index + 1), text: String(repeating: "x", count: 2_000))
        }
        let bounded = try #require(try WeeklyConsolidator.makePreparation(
            snapshot: crowded, for: Self.now, calendar: Self.calendar()
        ))
        #expect(bounded.input.sources.count <= WeeklyConsolidator.maximumSources)
        #expect(bounded.input.requestText.count <= WeeklyConsolidator.maximumRequestCharacters)
        #expect(bounded.omittedSourceCount > 0)
        #expect(bounded.input.sources.map(\.id) == bounded.input.sources.map(\.id).sorted {
            $0.uuidString.lowercased() < $1.uuidString.lowercased()
        })
    }

    @Test("Empty vault produces no preparation")
    func emptyVault() throws {
        let result = try WeeklyConsolidator.makePreparation(
            snapshot: SeededData.emptySnapshot, for: Self.now, calendar: Self.calendar()
        )
        #expect(result == nil)
    }

    @Test("OpenRouter receives the canonical weekly request byte for byte")
    func exactOpenRouterContent() async throws {
        let preparation = try #require(try WeeklyConsolidator.makePreparation(
            snapshot: Self.snapshot(), for: Self.now, calendar: Self.calendar()
        ))
        let transport = WeeklyTransport(response: Self.providerResponse(input: preparation.input))
        let model = OpenRouterLanguageModel(
            keyProvider: WeeklyKeyProvider(),
            configurationProvider: WeeklyConfigurationProvider(),
            transport: transport
        )

        _ = try await model.consolidateWeek(preparation.input)

        let request = try #require(await transport.requests.first)
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.last?["content"] as? String == preparation.input.requestText)
        #expect(body["response_format"] != nil)
    }

    @Test("Validator enforces schema, citations, provenance, and safety")
    func validationBoundaries() throws {
        let preparation = try #require(try WeeklyConsolidator.makePreparation(
            snapshot: Self.snapshot(), for: Self.now, calendar: Self.calendar()
        ))
        let validator = OrganizerOutputValidator()
        let valid = Self.result(for: preparation.input)
        #expect(try validator.validatedWeeklySummary(valid, input: preparation.input) == valid)

        let source = preparation.input.sources[0]
        let citation = EvidenceCitation(sourceID: source.id, quote: source.document.text, timestampMilliseconds: nil)
        let invalidItems = [
            WeeklySummaryItem(id: UUID(), text: "Fabricated", provenance: .user,
                              evidence: [EvidenceCitation(sourceID: UUID(), quote: "Fabricated", timestampMilliseconds: nil)]),
            WeeklySummaryItem(id: UUID(), text: "Provider observation", provenance: .provider, evidence: [citation]),
            WeeklySummaryItem(id: UUID(), text: "TMS caused mood improvement.", provenance: .user, evidence: [citation]),
            WeeklySummaryItem(id: UUID(), text: "You should change your medication.", provenance: .user, evidence: [citation]),
            WeeklySummaryItem(id: UUID(), text: "Try an exposure to provoke distress.", provenance: .user, evidence: [citation]),
            WeeklySummaryItem(id: UUID(), text: "This caused improvement.", provenance: .candyCorn, evidence: [citation]),
        ]
        for item in invalidItems {
            #expect(throws: AIProviderError.invalidResponse) {
                _ = try validator.validatedWeeklySummary(Self.result(for: preparation.input, firstItem: item), input: preparation.input)
            }
        }

        var duplicateSections = valid.sections
        duplicateSections[1] = WeeklySummarySection(
            id: duplicateSections[1].id,
            kind: .moodTrend,
            items: duplicateSections[1].items
        )
        #expect(throws: AIProviderError.invalidResponse) {
            _ = try validator.validatedWeeklySummary(WeeklySummaryResult(
                interval: valid.interval, sections: duplicateSections, metadata: valid.metadata
            ), input: preparation.input)
        }
    }

    @MainActor
    @Test("DemoState prepares consent, persists once, reloads, and opens the next week")
    func consentPersistenceAndScheduling() async throws {
        let clock = LockedDate(Self.now)
        let model = WeeklyLanguageModel()
        let fixture = try await Self.stateFixture(snapshot: Self.snapshot(), model: model, clock: clock)

        async let first = fixture.state.refreshWeeklySummary()
        async let second = fixture.state.refreshWeeklySummary()
        let pending = try #require(await first)
        #expect(try await second == pending)
        #expect(await model.callCount == 0)
        #expect(pending.disclosure.totalCharacterCount > 0)
        #expect(await fixture.state.performAISend(pending))
        #expect(!(await fixture.state.performAISend(pending)))
        #expect(await model.callCount == 1)
        #expect(fixture.state.currentWeeklySummary?.sections.map(\.kind) == WeeklySummarySectionKind.allCases)
        #expect(try await fixture.state.refreshWeeklySummary() == nil)
        #expect((await fixture.store.snapshot()).artifacts.filter { $0.kind == .weeklySummary }.count == 1)

        let reloaded = DemoState(dependencies: fixture.dependencies, arguments: ["CandyCorn"])
        await reloaded.load()
        #expect(reloaded.currentWeeklySummary != nil)
        #expect(try await reloaded.refreshWeeklySummary() == nil)

        clock.set(Self.now.addingTimeInterval(8 * 24 * 60 * 60))
        #expect(reloaded.currentWeeklySummary == nil)
        #expect(try await reloaded.refreshWeeklySummary() != nil)
        #expect(await model.callCount == 1)
    }

    @MainActor
    @Test("AI gates, empty data, stale input, and provider failure never persist summaries")
    func gatesAndFailures() async throws {
        let clock = LockedDate(Self.now)
        let offModel = WeeklyLanguageModel()
        var off = Self.snapshot()
        off.settings.aiMode = .off
        off.settings.aiProvider = .off
        let offFixture = try await Self.stateFixture(snapshot: off, model: offModel, clock: clock)
        await #expect(throws: UserFacingError.self) { _ = try await offFixture.state.refreshWeeklySummary() }
        #expect(await offModel.callCount == 0)

        let missingModel = WeeklyLanguageModel()
        let missing = try await Self.stateFixture(snapshot: Self.snapshot(), model: missingModel, clock: clock, hasKey: false)
        await #expect(throws: UserFacingError.self) { _ = try await missing.state.refreshWeeklySummary() }
        #expect(await missingModel.callCount == 0)

        let emptyModel = WeeklyLanguageModel()
        var empty = SeededData.emptySnapshot
        empty.settings.aiMode = .organizer
        empty.settings.aiProvider = .router
        let emptyFixture = try await Self.stateFixture(snapshot: empty, model: emptyModel, clock: clock)
        #expect(try await emptyFixture.state.refreshWeeklySummary() == nil)
        #expect(await emptyModel.callCount == 0)

        let staleModel = WeeklyLanguageModel()
        let stale = try await Self.stateFixture(snapshot: Self.snapshot(), model: staleModel, clock: clock)
        let stalePending = try #require(await stale.state.refreshWeeklySummary())
        var changed = Self.journal(id: Self.journalID, text: "Changed after disclosure")
        changed.updatedAt = Self.now.addingTimeInterval(1)
        await stale.store.saveJournal(changed)
        #expect(!(await stale.state.performAISend(stalePending)))
        #expect(await staleModel.callCount == 0)

        let failedModel = WeeklyLanguageModel(fails: true)
        let failed = try await Self.stateFixture(snapshot: Self.snapshot(), model: failedModel, clock: clock)
        let failedPending = try #require(await failed.state.refreshWeeklySummary())
        #expect(!(await failed.state.performAISend(failedPending)))
        #expect(await failedModel.callCount == 1)
        #expect((await failed.store.snapshot()).artifacts.filter { $0.kind == .weeklySummary }.isEmpty)
    }

    @Test("Unreadable current artifact does not suppress preparation")
    func unreadableArtifact() async throws {
        var snapshot = Self.snapshot()
        snapshot.artifacts = [AIArtifact(
            id: UUID(), kind: .weeklySummary, sourceIDs: [Self.journalID],
            provider: "fixture", model: "fixture/model", structuredPayload: Data([0xff]), createdAt: Self.now
        )]
        #expect(WeeklyConsolidator.currentSummary(
            in: snapshot.artifacts, for: Self.now, calendar: Self.calendar()
        ) == nil)
        let preparation = try await WeeklyConsolidator(
            careStore: InMemoryCareStore(snapshot: snapshot),
            languageModel: WeeklyLanguageModel(), calendar: Self.calendar(), now: { Self.now }
        ).prepareSummary(for: Self.now)
        #expect(preparation != nil)
    }

    fileprivate static func result(
        for input: WeeklySummaryInput,
        firstItem: WeeklySummaryItem? = nil
    ) -> WeeklySummaryResult {
        let source = input.sources[0]
        let item = firstItem ?? WeeklySummaryItem(
            id: UUID(),
            text: source.provenance == .candyCorn ? "This was recorded." : source.document.text,
            provenance: source.provenance,
            evidence: [EvidenceCitation(sourceID: source.id, quote: source.document.text, timestampMilliseconds: nil)]
        )
        let sections = WeeklySummarySectionKind.allCases.enumerated().map { index, kind in
            WeeklySummarySection(id: UUID(), kind: kind, items: index == 0 ? [item] : [])
        }
        return WeeklySummaryResult(
            interval: input.interval,
            sections: sections,
            metadata: AIResultMetadata(provider: "fixture", model: "fixture/model", usage: AIUsage())
        )
    }

    private static func snapshot() -> CareSnapshot {
        var snapshot = SeededData.emptySnapshot
        snapshot.settings.aiMode = .organizer
        snapshot.settings.aiProvider = .router
        snapshot.journals = [journal(id: journalID, text: "I completed my walk and felt steady.")]
        snapshot.goals = [Goal(
            id: goalID, title: "Walk after lunch", detail: "Ten minutes", cadence: .daily,
            source: .userExplicit, sourceEntityID: nil, sourceTimestampMilliseconds: nil,
            status: .active, createdAt: now.addingTimeInterval(-30 * 24 * 60 * 60), targetDate: nil,
            provenance: Provenance(
                voice: .user, label: "You chose this", detail: "Fixture", occurredAt: now, sourceRoute: nil
            )
        )]
        return snapshot
    }

    private static func journal(id: UUID, text: String) -> JournalEntry {
        JournalEntry(
            id: id, createdAt: now, updatedAt: now, inputType: .text,
            title: "Weekly journal", rawText: text, cleanedText: nil,
            summaryItems: [], originalAttachmentID: nil, audioAttachmentID: nil, moodLogID: nil,
            pinnedForNextAppointment: false, processingStatus: .processed,
            provenance: Provenance(
                voice: .user, label: "You wrote this", detail: "Fixture", occurredAt: now, sourceRoute: nil
            )
        )
    }

    private static func talkingPoint(createdAt: Date) -> TalkingPoint {
        TalkingPoint(
            id: UUID(uuidString: "40000000-0000-0000-0000-000000000001")!,
            text: "Ask about sleep", source: .manual, sourceID: nil,
            targetAppointmentKind: nil, isImportant: true, status: .open, createdAt: createdAt,
            provenance: Provenance(
                voice: .user, label: "You added this", detail: "Fixture", occurredAt: createdAt, sourceRoute: nil
            )
        )
    }

    private static func providerResponse(input: WeeklySummaryInput) -> Data {
        let source = input.sources[0]
        let sections: [[String: Any]] = WeeklySummarySectionKind.allCases.enumerated().map { index, kind in
            let items: [[String: Any]] = index == 0 ? [[
                "id": "50000000-0000-0000-0000-000000000001",
                "text": source.document.text,
                "provenance": source.provenance.rawValue,
                "evidence": [[
                    "sourceID": source.id.uuidString.lowercased(),
                    "quote": source.document.text,
                    "timestampMilliseconds": NSNull(),
                ]],
            ]] : []
            return [
                "id": String(format: "60000000-0000-0000-0000-%012d", index + 1),
                "kind": kind.rawValue,
                "items": items,
            ]
        }
        let content = (try? JSONSerialization.data(
            withJSONObject: ["sections": sections], options: [.sortedKeys]
        )) ?? Data()
        let envelope: [String: Any] = [
            "model": "fixture/model",
            "choices": [[
                "message": ["content": String(data: content, encoding: .utf8) ?? ""],
                "finish_reason": "stop",
            ]],
        ]
        return (try? JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])) ?? Data()
    }

    @MainActor
    private static func stateFixture(
        snapshot: CareSnapshot,
        model: WeeklyLanguageModel,
        clock: LockedDate,
        hasKey: Bool = true
    ) async throws -> WeeklyStateFixture {
        let store = InMemoryCareStore(snapshot: snapshot)
        let attachments = InMemoryAttachmentStore()
        let keyStore = InMemoryOpenRouterAPIKeyStore()
        if hasKey { try keyStore.storeKey("fictional-test-key") }
        let dependencies = AppDependencies(
            careStore: store, maintenance: store, attachments: attachments,
            recording: FakeRecordingService(attachments: attachments), playback: FakeAudioPlaybackService(),
            photos: FakePhotoAttachmentService(), exporter: FakeVaultExporter(store: store, attachments: attachments),
            logger: NoOpEventLogger(), languageModel: model, openRouterKeyStore: keyStore,
            screenshotMode: false, now: { clock.get() }
        )
        let state = DemoState(dependencies: dependencies, arguments: ["CandyCorn"])
        await state.load()
        return WeeklyStateFixture(state: state, store: store, dependencies: dependencies)
    }

    private static func calendar(firstWeekday: Int = 2) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = firstWeekday
        calendar.minimumDaysInFirstWeek = 1
        return calendar
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int) -> Date {
        Self.calendar().date(from: DateComponents(
            timeZone: Self.calendar().timeZone, year: year, month: month, day: day, hour: hour
        ))!
    }

    private static func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
}

@MainActor
private struct WeeklyStateFixture {
    let state: DemoState
    let store: InMemoryCareStore
    let dependencies: AppDependencies
}

private actor WeeklyLanguageModel: CandyCornLanguageModel {
    nonisolated let id = "weekly-fixture"
    private let fails: Bool
    private(set) var callCount = 0
    private(set) var input: WeeklySummaryInput?

    init(fails: Bool = false) { self.fails = fails }

    func consolidateWeek(_ input: WeeklySummaryInput) throws -> WeeklySummaryResult {
        callCount += 1
        self.input = input
        if fails { throw AIProviderError.serviceUnavailable }
        return WeeklyConsolidatorTests.result(for: input)
    }

    func rewriteJournal(_ input: RewriteJournalInput) throws -> RewriteJournalResult {
        _ = input.source.id
        throw AIProviderError.unavailable
    }

    func summarizeJournal(_ input: JournalSummaryInput) throws -> JournalSummaryResult {
        _ = input.source.id
        throw AIProviderError.unavailable
    }

    func extractJournalSignals(_ input: JournalSignalInput) throws -> JournalSignalResult {
        _ = input.source.id
        throw AIProviderError.unavailable
    }

    func summarizeSession(_ input: SessionSummaryInput) throws -> SessionSummaryResult {
        _ = input.appointmentID
        throw AIProviderError.unavailable
    }

    func generateAppointmentBrief(_ input: AppointmentBriefInput) throws -> AppointmentBriefResult {
        _ = input.appointmentKind
        throw AIProviderError.unavailable
    }
}

private actor WeeklyTransport: AIHTTPTransport {
    private let response: Data
    private(set) var requests: [URLRequest] = []

    init(response: Data) { self.response = response }

    func send(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil
              ) else {
            throw URLError(.badServerResponse)
        }
        return (self.response, response)
    }
}

private struct WeeklyKeyProvider: OpenRouterAPIKeyProviding {
    func readKey() throws -> String? { "fictional-test-key" }
    func storeKey(_ value: String) throws { _ = value }
    func removeKey() throws {}
    func hasKey() throws -> Bool { true }
}

private struct WeeklyConfigurationProvider: AIConfigurationProviding {
    func load() -> AIModelConfiguration { .defaults }
    func save(_ configuration: AIModelConfiguration) throws { _ = configuration }
    func reset() throws {}
}

private final class LockedDate: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date) { self.value = value }

    func get() -> Date {
        lock.withLock { value }
    }

    func set(_ value: Date) {
        lock.withLock { self.value = value }
    }
}
