import SwiftUI

struct SessionDebriefContent: Equatable {
    static let sectionTitles = [
        "What you talked about",
        "What your provider asked you to do",
        "Things that sounded like goals",
        "Talking points you brought that got discussed",
        "Questions left open",
    ]

    let topics: [StructuredSessionSummaryItem]
    let providerRequests: [StructuredSessionSummaryItem]
    let candidateGoals: [StructuredSessionSummaryItem]
    let discussedTalkingPoints: [StructuredSessionSummaryItem]
    let openQuestions: [StructuredSessionSummaryItem]

    init(result: StructuredSessionSummaryResult) {
        topics = result.debriefTopics
        providerRequests = Self.items(
            in: result,
            kinds: result.template == .therapy ? [.homework] : [.providerInstructions]
        ).filter { $0.provenance == .provider }
        candidateGoals = Self.items(in: result, kinds: [.goals])
        discussedTalkingPoints = result.discussedTalkingPoints.filter(Self.isActionable)
        openQuestions = Self.unique(Self.items(
            in: result,
            kinds: result.template == .therapy
                ? [.questionsToRevisit, .unfinishedTopics, .nextSessionItems]
                : [.questionsForProvider, .thingsToMonitor, .nextSessionItems]
        ))
    }

    var isUsable: Bool {
        (3...5).contains(topics.count) && topics.allSatisfy(Self.isActionable)
    }

    static func firstTimestamp(in item: StructuredSessionSummaryItem) -> Int? {
        item.evidence.lazy.compactMap(\.timestampMilliseconds).first { $0 >= 0 }
    }

    private static func items(
        in result: StructuredSessionSummaryResult,
        kinds: Set<SessionSummarySectionKind>
    ) -> [StructuredSessionSummaryItem] {
        result.sections
            .filter { kinds.contains($0.kind) }
            .flatMap(\.items)
            .filter(isActionable)
    }

    private static func unique(_ items: [StructuredSessionSummaryItem]) -> [StructuredSessionSummaryItem] {
        var seen: Set<UUID> = []
        return items.filter { seen.insert($0.id).inserted }
    }

    private static func isActionable(_ item: StructuredSessionSummaryItem) -> Bool {
        !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && firstTimestamp(in: item) != nil
    }
}

enum SessionDebriefMutationFactory {
    static func addHomework(
        item: StructuredSessionSummaryItem,
        appointment: Appointment,
        goalID: UUID,
        decisionID: UUID,
        createdAt: Date
    ) -> SessionDebriefMutation? {
        guard item.provenance == .provider,
              let goal = goal(
                  item: item, appointment: appointment, title: item.text,
                  cadence: .homework, id: goalID, createdAt: createdAt
              ) else { return nil }
        let decision = decision(
            id: decisionID, appointmentID: appointment.id, itemID: item.id,
            kind: .addedHomework, targetID: goal.id, editedText: nil, createdAt: createdAt
        )
        return .addGoal(decision: decision, goal: goal)
    }

    static func addGoal(
        item: StructuredSessionSummaryItem,
        appointment: Appointment,
        editedText: String?,
        goalID: UUID,
        decisionID: UUID,
        createdAt: Date
    ) -> SessionDebriefMutation? {
        let title = editedText ?? item.text
        guard let goal = goal(
            item: item, appointment: appointment, title: title,
            cadence: .oneOff, id: goalID, createdAt: createdAt
        ) else { return nil }
        let normalizedEdit = editedText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let decision = decision(
            id: decisionID, appointmentID: appointment.id, itemID: item.id,
            kind: .addedGoal, targetID: goal.id, editedText: normalizedEdit,
            createdAt: createdAt
        )
        return .addGoal(decision: decision, goal: goal)
    }

    static func ignoreGoal(
        item: StructuredSessionSummaryItem,
        appointmentID: UUID,
        decisionID: UUID,
        createdAt: Date
    ) -> SessionDebriefMutation {
        .ignoreGoal(decision: decision(
            id: decisionID, appointmentID: appointmentID, itemID: item.id,
            kind: .ignoredGoal, targetID: nil, editedText: nil, createdAt: createdAt
        ))
    }

    static func markDiscussed(
        item: StructuredSessionSummaryItem,
        appointmentID: UUID,
        talkingPoints: [TalkingPoint],
        decisionID: UUID,
        createdAt: Date
    ) -> SessionDebriefMutation? {
        guard let relatedID = item.relatedEntityID,
              var point = talkingPoints.first(where: {
                  $0.id == relatedID && $0.status == .open
              }) else { return nil }
        point.status = .discussed
        let decision = decision(
            id: decisionID, appointmentID: appointmentID, itemID: item.id,
            kind: .markedTalkingPointDiscussed, targetID: point.id,
            editedText: nil, createdAt: createdAt
        )
        return .markTalkingPointDiscussed(decision: decision, talkingPoint: point)
    }

    static func pinQuestion(
        item: StructuredSessionSummaryItem,
        appointment: Appointment,
        talkingPointID: UUID,
        decisionID: UUID,
        createdAt: Date
    ) -> SessionDebriefMutation? {
        let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, SessionDebriefContent.firstTimestamp(in: item) != nil else { return nil }
        let point = TalkingPoint(
            id: talkingPointID, text: text, source: .session, sourceID: appointment.id,
            targetAppointmentKind: appointment.kind, isImportant: false, status: .open,
            createdAt: createdAt, provenance: provenance(for: item, appointment: appointment)
        )
        let decision = decision(
            id: decisionID, appointmentID: appointment.id, itemID: item.id,
            kind: .pinnedQuestion, targetID: point.id, editedText: nil, createdAt: createdAt
        )
        return .pinQuestion(decision: decision, talkingPoint: point)
    }

    private static func goal(
        item: StructuredSessionSummaryItem,
        appointment: Appointment,
        title: String,
        cadence: Goal.Cadence,
        id: UUID,
        createdAt: Date
    ) -> Goal? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let timestamp = SessionDebriefContent.firstTimestamp(in: item) else { return nil }
        return Goal(
            id: id, title: trimmed, detail: nil, cadence: cadence,
            source: source(for: item.provenance), sourceEntityID: appointment.id,
            sourceTimestampMilliseconds: timestamp, status: .active, createdAt: createdAt,
            targetDate: nil, provenance: provenance(for: item, appointment: appointment)
        )
    }

    private static func decision(
        id: UUID,
        appointmentID: UUID,
        itemID: UUID,
        kind: SessionDebriefDecisionKind,
        targetID: UUID?,
        editedText: String?,
        createdAt: Date
    ) -> SessionDebriefDecision {
        SessionDebriefDecision(
            id: id, appointmentID: appointmentID, summaryItemID: itemID,
            kind: kind, targetEntityID: targetID, editedText: editedText,
            createdAt: createdAt
        )
    }

    private static func source(for voice: SessionSummaryItemProvenance) -> Goal.Source {
        switch voice {
        case .patient: .userExplicit
        case .provider: .providerExplicit
        case .candyCorn: .aiSuggested
        }
    }

    private static func provenance(
        for item: StructuredSessionSummaryItem,
        appointment: Appointment
    ) -> Provenance {
        let identity: (ProvenanceVoice, String) = switch item.provenance {
        case .patient: (.user, "You said this")
        case .provider: (.provider, "Your provider said this")
        case .candyCorn: (.candyCorn, "Candy Corn found this")
        }
        return Provenance(
            voice: identity.0, label: identity.1, detail: "From this session debrief",
            occurredAt: appointment.endedAt ?? appointment.startedAt ?? appointment.scheduledAt,
            sourceRoute: .sessionDebrief
        )
    }
}

enum SessionDebriefDecisionPresentation {
    static func completion(
        for itemID: UUID,
        appointmentID: UUID,
        decisions: [SessionDebriefDecision]
    ) -> String? {
        guard let kind = decisions.first(where: {
            $0.appointmentID == appointmentID && $0.summaryItemID == itemID
        })?.kind else { return nil }
        return switch kind {
        case .addedHomework: "Added to homework"
        case .addedGoal: "Added"
        case .ignoredGoal: "Ignored"
        case .markedTalkingPointDiscussed: "Marked discussed"
        case .pinnedQuestion: "Pinned"
        }
    }
}

enum SessionDebriefTimestamp {
    static func accessibilityLabel(milliseconds: Int) -> String {
        let seconds = max(0, milliseconds / 1_000)
        return "Play from \(seconds / 60) minutes \(seconds % 60) seconds"
    }
}

enum SessionDebriefAvailability: Equatable {
    case processing
    case ready(StructuredSessionSummaryResult)
    case unavailable

    static func resolve(
        appointment: Appointment,
        record: SessionProcessingRecord?,
        result: StructuredSessionSummaryResult?
    ) -> Self {
        guard record?.stage == .ready else { return .processing }
        let expectedTemplate: SessionSummaryTemplate = appointment.kind == .tms ? .tms : .therapy
        guard let result, result.template == expectedTemplate,
              SessionDebriefContent(result: result).isUsable else { return .unavailable }
        return .ready(result)
    }
}

@MainActor
enum SessionDebriefNavigation {
    static func finish(_ navigation: NavigationModel) {
        navigation.navigate(to: .today)
    }
}

struct SessionDebriefView: View {
    @Bindable var navigation: NavigationModel
    @Bindable var state: DemoState
    @State private var inFlightItemIDs: Set<UUID> = []
    @State private var itemErrors: [UUID: String] = [:]
    @State private var editingGoal: SessionDebriefEditDraft?

    var body: some View {
        V2Screen(
            title: "Session debrief",
            subtitle: appointmentMetadata,
            backAction: navigation.backAction(for: .sessionDebrief)
        ) {
            if let appointment = sessionAppointment {
                debrief(for: appointment)
            } else {
                unavailable(message: "No processed therapy or TMS session is available yet.")
            }
        }
        .sheet(item: $editingGoal) { draft in
            SessionDebriefGoalEditSheet(
                draft: draft,
                onCancel: { editingGoal = nil },
                onSave: { text in await saveEditedGoal(draft.item, text: text) }
            )
        }
    }

    @ViewBuilder
    private func debrief(for appointment: Appointment) -> some View {
        let record = state.sessionProcessingRecord(for: appointment.id)
        switch SessionDebriefAvailability.resolve(
            appointment: appointment,
            record: record,
            result: state.structuredSessionSummary(for: appointment.id)?.result
        ) {
        case .processing:
            SessionProcessingStatusView(
                record: record,
                onReviewSummary: { backToSession(appointment) },
                onRetry: {
                    Task { await state.retrySessionProcessing(appointmentID: appointment.id) }
                },
                onOpenDebrief: {}
            )
            Button("Back to session detail") { backToSession(appointment) }
                .buttonStyle(SecondaryButtonStyle())
        case let .ready(result):
            readyDebrief(SessionDebriefContent(result: result), appointment: appointment)
        case .unavailable:
            unavailable(
                message: "Candy Corn could not read a complete debrief. Your transcript and recording remain available."
            )
            Button("Back to session detail") { backToSession(appointment) }
                .buttonStyle(SecondaryButtonStyle())
        }
    }

    @ViewBuilder
    private func readyDebrief(_ content: SessionDebriefContent, appointment: Appointment) -> some View {
        acknowledgement
        topicsSection(content.topics, appointment: appointment)
        providerRequestsSection(content.providerRequests, appointment: appointment)
        candidateGoalsSection(content.candidateGoals, appointment: appointment)
        discussedSection(content.discussedTalkingPoints, appointment: appointment)
        questionsSection(content.openQuestions, appointment: appointment)
        Button("Done") { SessionDebriefNavigation.finish(navigation) }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityHint("Returns to Today without changing any debrief choices")
    }

    private var acknowledgement: some View {
        V2Card(background: DesignTokens.surfaceWarm) {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.compact) {
                IconTile(icon: .quote)
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                    Text("You showed up. Here is what came out of it.")
                        .font(TypeScale.cardTitle)
                        .foregroundStyle(DesignTokens.cocoa)
                        .fixedSize(horizontal: false, vertical: true)
                    ProvenanceInline(voice: .candyCorn, text: "Candy Corn")
                }
            }
        }
    }

    private func topicsSection(
        _ items: [StructuredSessionSummaryItem],
        appointment: Appointment
    ) -> some View {
        V2GroupCard(title: SessionDebriefContent.sectionTitles[0]) {
            if items.isEmpty {
                emptyRow
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                        Text(item.text)
                            .font(TypeScale.body)
                            .foregroundStyle(DesignTokens.cocoa)
                            .fixedSize(horizontal: false, vertical: true)
                        ProvenanceStack(provenance: provenance(for: item, appointment: appointment))
                        if let timestamp = SessionDebriefContent.firstTimestamp(in: item) {
                            Button {
                                play(item: item, appointmentID: appointment.id, timestamp: timestamp)
                            } label: {
                                Label(
                                    "Play from \(AppointmentRecordingClock.format(milliseconds: timestamp))",
                                    systemImage: AppIcon.play.rawValue
                                )
                                .font(TypeScale.metaStrong)
                                .frame(minHeight: DesignTokens.controlMinimum)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(DesignTokens.orangePressed)
                            .accessibilityLabel(
                                SessionDebriefTimestamp.accessibilityLabel(milliseconds: timestamp)
                            )
                        }
                        errorNotice(for: item.id)
                    }
                    .padding(DesignTokens.Spacing.base)
                    .overlay(alignment: .top) {
                        if index > 0 {
                            Rectangle().fill(DesignTokens.hairline).frame(height: 1)
                        }
                    }
                }
            }
        }
    }

    private func providerRequestsSection(
        _ items: [StructuredSessionSummaryItem],
        appointment: Appointment
    ) -> some View {
        actionSection(title: SessionDebriefContent.sectionTitles[1], items: items) { item in
            if let completion = completion(for: item, appointmentID: appointment.id) {
                completionText(completion)
            } else {
                Button("Add to homework") { addHomework(item, appointment: appointment) }
                    .buttonStyle(CompactDarkButtonStyle())
                    .disabled(inFlightItemIDs.contains(item.id))
            }
        }
    }

    private func candidateGoalsSection(
        _ items: [StructuredSessionSummaryItem],
        appointment: Appointment
    ) -> some View {
        actionSection(title: SessionDebriefContent.sectionTitles[2], items: items) { item in
            if let completion = completion(for: item, appointmentID: appointment.id) {
                completionText(completion)
            } else {
                adaptiveActions(
                    primary: ("Add", { addGoal(item, appointment: appointment, editedText: nil) }),
                    secondary: ("Edit", { editingGoal = SessionDebriefEditDraft(item: item) }),
                    tertiary: ("Ignore", { ignoreGoal(item, appointment: appointment) }),
                    disabled: inFlightItemIDs.contains(item.id)
                )
            }
        }
    }

    private func discussedSection(
        _ items: [StructuredSessionSummaryItem],
        appointment: Appointment
    ) -> some View {
        actionSection(title: SessionDebriefContent.sectionTitles[3], items: items) { item in
            if let completion = completion(for: item, appointmentID: appointment.id) {
                completionText(completion)
            } else if canMarkDiscussed(item) {
                Button("Mark discussed") { markDiscussed(item, appointment: appointment) }
                    .buttonStyle(CompactGhostButtonStyle())
                    .disabled(inFlightItemIDs.contains(item.id))
            } else {
                Text("This talking point is no longer available.")
                    .font(TypeScale.meta)
                    .foregroundStyle(DesignTokens.cocoaSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func questionsSection(
        _ items: [StructuredSessionSummaryItem],
        appointment: Appointment
    ) -> some View {
        actionSection(title: SessionDebriefContent.sectionTitles[4], items: items) { item in
            if let completion = completion(for: item, appointmentID: appointment.id) {
                completionText(completion)
            } else {
                Button("Pin for next time") { pinQuestion(item, appointment: appointment) }
                    .buttonStyle(CompactGhostButtonStyle())
                    .disabled(inFlightItemIDs.contains(item.id))
            }
        }
    }

    private func actionSection<Actions: View>(
        title: String,
        items: [StructuredSessionSummaryItem],
        @ViewBuilder actions: @escaping (StructuredSessionSummaryItem) -> Actions
    ) -> some View {
        V2GroupCard(title: title) {
            if items.isEmpty {
                emptyRow
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                        Text(item.text)
                            .font(TypeScale.body)
                            .foregroundStyle(DesignTokens.cocoa)
                            .fixedSize(horizontal: false, vertical: true)
                        ProvenanceInline(voice: voice(for: item), text: provenanceLabel(for: item))
                        actions(item)
                        errorNotice(for: item.id)
                    }
                    .padding(DesignTokens.Spacing.base)
                    .overlay(alignment: .top) {
                        if index > 0 {
                            Rectangle().fill(DesignTokens.hairline).frame(height: 1)
                        }
                    }
                }
            }
        }
    }

    private var emptyRow: some View {
        V2ListRow(
            icon: nil, title: "Nothing was suggested here.", trailing: .none,
            divider: false, disabled: true
        )
    }

    private func unavailable(message: String) -> some View {
        StatusNotice(title: "Debrief unavailable", detail: message, kind: .warning)
    }

    @ViewBuilder
    private func errorNotice(for itemID: UUID) -> some View {
        if let message = itemErrors[itemID] {
            StatusNotice(title: "Choice not saved", detail: message, kind: .warning)
        }
    }

    private func completionText(_ text: String) -> some View {
        Label(text, systemImage: AppIcon.check.rawValue)
            .font(TypeScale.metaStrong)
            .foregroundStyle(DesignTokens.sage)
            .frame(minHeight: DesignTokens.controlMinimum, alignment: .leading)
            .accessibilityLabel(text)
    }

    private func adaptiveActions(
        primary: (String, () -> Void),
        secondary: (String, () -> Void),
        tertiary: (String, () -> Void),
        disabled: Bool
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DesignTokens.Spacing.small) {
                compactAction(primary, dark: true, disabled: disabled)
                compactAction(secondary, dark: false, disabled: disabled)
                compactAction(tertiary, dark: false, disabled: disabled)
            }
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                compactAction(primary, dark: true, disabled: disabled)
                compactAction(secondary, dark: false, disabled: disabled)
                compactAction(tertiary, dark: false, disabled: disabled)
            }
        }
    }

    @ViewBuilder
    private func compactAction(
        _ value: (String, () -> Void),
        dark: Bool,
        disabled: Bool
    ) -> some View {
        if dark {
            Button(value.0, action: value.1)
                .buttonStyle(CompactDarkButtonStyle())
                .disabled(disabled)
        } else {
            Button(value.0, action: value.1)
                .buttonStyle(CompactGhostButtonStyle())
                .disabled(disabled)
        }
    }

    private var sessionAppointment: Appointment? {
        let supported = state.appointments.filter { $0.kind == .therapy || $0.kind == .tms }
        if let id = state.selectedAppointmentID,
           let selected = supported.first(where: { $0.id == id }),
           isReadyWithValidSummary(selected) {
            return selected
        }
        if let ready = supported.filter(isReadyWithValidSummary).max(by: isEarlier) { return ready }
        if let id = state.selectedAppointmentID,
           let selected = supported.first(where: { $0.id == id }) { return selected }
        return supported
            .filter { state.sessionProcessingRecord(for: $0.id) != nil }
            .max(by: isEarlier)
    }

    private func isReadyWithValidSummary(_ appointment: Appointment) -> Bool {
        if case .ready = SessionDebriefAvailability.resolve(
            appointment: appointment,
            record: state.sessionProcessingRecord(for: appointment.id),
            result: state.structuredSessionSummary(for: appointment.id)?.result
        ) { return true }
        return false
    }

    private func isEarlier(_ lhs: Appointment, _ rhs: Appointment) -> Bool {
        (lhs.endedAt ?? lhs.startedAt ?? lhs.scheduledAt ?? .distantPast)
            < (rhs.endedAt ?? rhs.startedAt ?? rhs.scheduledAt ?? .distantPast)
    }

    private var appointmentMetadata: String {
        guard let appointment = sessionAppointment else { return "Saved sessions" }
        let date = (appointment.endedAt ?? appointment.startedAt ?? appointment.scheduledAt)?
            .formatted(.dateTime.month(.abbreviated).day()) ?? "Date not recorded"
        return "\(appointment.kind.displayName) with \(appointment.providerName) · \(date)"
    }

    private func completion(
        for item: StructuredSessionSummaryItem,
        appointmentID: UUID
    ) -> String? {
        SessionDebriefDecisionPresentation.completion(
            for: item.id, appointmentID: appointmentID, decisions: state.debriefDecisions
        )
    }

    private func canMarkDiscussed(_ item: StructuredSessionSummaryItem) -> Bool {
        guard let relatedID = item.relatedEntityID else { return false }
        return state.talkingPoints.contains { $0.id == relatedID && $0.status == .open }
    }

    private func addHomework(_ item: StructuredSessionSummaryItem, appointment: Appointment) {
        guard let mutation = SessionDebriefMutationFactory.addHomework(
            item: item, appointment: appointment, goalID: UUID(), decisionID: UUID(),
            createdAt: state.dependencies.now()
        ) else { return showInvalidAction(for: item.id) }
        apply(mutation, itemID: item.id, appointmentID: appointment.id)
    }

    private func addGoal(
        _ item: StructuredSessionSummaryItem,
        appointment: Appointment,
        editedText: String?
    ) {
        guard let mutation = SessionDebriefMutationFactory.addGoal(
            item: item, appointment: appointment, editedText: editedText,
            goalID: UUID(), decisionID: UUID(), createdAt: state.dependencies.now()
        ) else { return showInvalidAction(for: item.id) }
        apply(mutation, itemID: item.id, appointmentID: appointment.id)
    }

    private func ignoreGoal(_ item: StructuredSessionSummaryItem, appointment: Appointment) {
        let mutation = SessionDebriefMutationFactory.ignoreGoal(
            item: item, appointmentID: appointment.id, decisionID: UUID(),
            createdAt: state.dependencies.now()
        )
        apply(mutation, itemID: item.id, appointmentID: appointment.id)
    }

    private func markDiscussed(_ item: StructuredSessionSummaryItem, appointment: Appointment) {
        guard let mutation = SessionDebriefMutationFactory.markDiscussed(
            item: item, appointmentID: appointment.id, talkingPoints: state.talkingPoints,
            decisionID: UUID(), createdAt: state.dependencies.now()
        ) else { return showInvalidAction(for: item.id) }
        apply(mutation, itemID: item.id, appointmentID: appointment.id)
    }

    private func pinQuestion(_ item: StructuredSessionSummaryItem, appointment: Appointment) {
        guard let mutation = SessionDebriefMutationFactory.pinQuestion(
            item: item, appointment: appointment, talkingPointID: UUID(), decisionID: UUID(),
            createdAt: state.dependencies.now()
        ) else { return showInvalidAction(for: item.id) }
        apply(mutation, itemID: item.id, appointmentID: appointment.id)
    }

    private func saveEditedGoal(_ item: StructuredSessionSummaryItem, text: String) async -> Bool {
        guard let appointment = sessionAppointment,
              !hasDecision(itemID: item.id, appointmentID: appointment.id),
              let mutation = SessionDebriefMutationFactory.addGoal(
                  item: item, appointment: appointment, editedText: text,
                  goalID: UUID(), decisionID: UUID(), createdAt: state.dependencies.now()
              ) else { return false }
        return await applyAndWait(mutation, itemID: item.id)
    }

    private func apply(
        _ mutation: SessionDebriefMutation,
        itemID: UUID,
        appointmentID: UUID
    ) {
        guard !hasDecision(itemID: itemID, appointmentID: appointmentID),
              !inFlightItemIDs.contains(itemID) else { return }
        Task { _ = await applyAndWait(mutation, itemID: itemID) }
    }

    private func applyAndWait(_ mutation: SessionDebriefMutation, itemID: UUID) async -> Bool {
        guard !inFlightItemIDs.contains(itemID) else { return false }
        inFlightItemIDs.insert(itemID)
        itemErrors[itemID] = nil
        let saved = await state.applyDebriefMutation(mutation)
        inFlightItemIDs.remove(itemID)
        if !saved {
            itemErrors[itemID] = "Try again. Your session and earlier choices are unchanged."
        }
        return saved
    }

    private func hasDecision(itemID: UUID, appointmentID: UUID) -> Bool {
        state.debriefDecisions.contains {
            $0.summaryItemID == itemID && $0.appointmentID == appointmentID
        }
    }

    private func play(item: StructuredSessionSummaryItem, appointmentID: UUID, timestamp: Int) {
        guard !inFlightItemIDs.contains(item.id) else { return }
        inFlightItemIDs.insert(item.id)
        itemErrors[item.id] = nil
        Task {
            let played = await state.playSessionRecording(
                appointmentID: appointmentID, fromMilliseconds: timestamp
            )
            inFlightItemIDs.remove(item.id)
            if !played {
                itemErrors[item.id] = "This recording is not available for playback."
            }
        }
    }

    private func showInvalidAction(for itemID: UUID) {
        itemErrors[itemID] = "This suggestion is missing its session source."
    }

    private func backToSession(_ appointment: Appointment) {
        navigation.navigate(to: appointment.kind == .tms ? .tmsPost : .therapySession)
    }

    private func voice(for item: StructuredSessionSummaryItem) -> ProvenanceVoice {
        switch item.provenance {
        case .patient: .user
        case .provider: .provider
        case .candyCorn: .candyCorn
        }
    }

    private func provenanceLabel(for item: StructuredSessionSummaryItem) -> String {
        switch item.provenance {
        case .patient: "You"
        case .provider: "Provider"
        case .candyCorn: "Candy Corn"
        }
    }

    private func provenance(
        for item: StructuredSessionSummaryItem,
        appointment: Appointment
    ) -> Provenance {
        Provenance(
            voice: voice(for: item), label: provenanceLabel(for: item),
            detail: "Linked to the processed transcript",
            occurredAt: appointment.endedAt ?? appointment.startedAt ?? appointment.scheduledAt,
            sourceRoute: .sessionDebrief
        )
    }

}

private struct SessionDebriefEditDraft: Identifiable {
    let item: StructuredSessionSummaryItem
    var id: UUID { item.id }
}

private struct SessionDebriefGoalEditSheet: View {
    let draft: SessionDebriefEditDraft
    let onCancel: () -> Void
    let onSave: (String) async -> Bool
    @State private var text: String
    @State private var isSaving = false

    init(
        draft: SessionDebriefEditDraft,
        onCancel: @escaping () -> Void,
        onSave: @escaping (String) async -> Bool
    ) {
        self.draft = draft
        self.onCancel = onCancel
        self.onSave = onSave
        _text = State(initialValue: draft.item.text)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Goal", text: $text, axis: .vertical)
                    .lineLimit(3...8)
            }
            .navigationTitle("Edit goal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel).disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Adding" : "Add edited goal") {
                        guard !isSaving else { return }
                        isSaving = true
                        Task {
                            if await onSave(text) { onCancel() }
                            isSaving = false
                        }
                    }
                    .disabled(
                        isSaving || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            }
        }
    }
}
