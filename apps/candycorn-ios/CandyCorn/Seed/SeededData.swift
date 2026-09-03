import Foundation

enum SeededData {
    static let patientName = "Jamie Rivera"
    static let therapyProviderName = "Dr. Elena Park"
    static let tmsProviderName = "Riverbend TMS team"

    static let footballJournalID = uuid("10000000-0000-0000-0000-000000000001")
    static let timelineJournalID = uuid("10000000-0000-0000-0000-000000000002")
    static let currentMoodID = uuid("20000000-0000-0000-0000-000000000001")
    static let upcomingTherapyID = uuid("30000000-0000-0000-0000-000000000001")
    static let completedTMSID = uuid("30000000-0000-0000-0000-000000000002")
    static let therapySessionID = uuid("30000000-0000-0000-0000-000000000003")

    static let journalEntries: [JournalEntry] = [
        JournalEntry(
            id: footballJournalID,
            createdAt: date(1_788_646_680),
            updatedAt: date(1_788_646_800),
            inputType: .voice,
            title: "Football and feeling guilty",
            rawText: "Work was fine until around three when I started thinking about football again. I got angry, went to the gym, and felt better. Then I realized I had not thought about it for a few hours, and I felt guilty about that.",
            cleanedText: "Work was going well until around 3 PM, when I started thinking about football again and became frustrated. Going to the gym helped. Later, I realized I had gone a few hours without thinking about football, and that made me feel guilty.",
            summaryItems: [
                "Football thoughts interrupted an otherwise steady workday.",
                "Exercise helped you feel better for a while.",
                "Feeling better was followed by guilt.",
            ],
            originalAttachmentID: nil,
            audioAttachmentID: uuid("11000000-0000-0000-0000-000000000001"),
            moodLogID: currentMoodID,
            pinnedForNextAppointment: true,
            processingStatus: .processed,
            provenance: provenance(.user, "You said this", "Journal, Sep 5 at 3:18 PM", 1_788_646_680, .journalDetail)
        ),
        JournalEntry(
            id: timelineJournalID,
            createdAt: date(1_788_476_760),
            updatedAt: date(1_788_476_760),
            inputType: .text,
            title: "The senior-year timeline",
            rawText: "I finished the senior-year section. What still bothers me is never getting the chance to prove I could have played.",
            cleanedText: "I finished writing the senior-year section. What still bothers me is that I never had the chance to prove I could have played.",
            summaryItems: [
                "Finished the assigned timeline.",
                "The missed chance to prove ability still feels unresolved.",
            ],
            originalAttachmentID: nil,
            audioAttachmentID: nil,
            moodLogID: nil,
            pinnedForNextAppointment: false,
            processingStatus: .processed,
            provenance: provenance(.user, "You wrote this", "Journal, Sep 3 at 4:06 PM", 1_788_476_760, .journalDetail)
        ),
    ]

    static let moodLogs: [MoodLog] = [
        MoodLog(
            id: currentMoodID,
            createdAt: date(1_788_654_600),
            mood: 6,
            anxiety: 7,
            energy: 4,
            customValues: [:],
            note: "Exercise helped today, then the guilt showed up."
        ),
    ]

    static let appointments: [Appointment] = [
        Appointment(id: upcomingTherapyID, kind: .therapy, scheduledAt: date(1_788_987_600), startedAt: nil, endedAt: nil, providerID: uuid("31000000-0000-0000-0000-000000000001"), providerName: therapyProviderName, recordingAttachmentID: nil, transcriptID: nil, summaryID: nil, status: .planned),
        Appointment(id: completedTMSID, kind: .tms, scheduledAt: date(1_788_625_800), startedAt: date(1_788_625_800), endedAt: date(1_788_627_120), providerID: uuid("31000000-0000-0000-0000-000000000002"), providerName: tmsProviderName, recordingAttachmentID: nil, transcriptID: nil, summaryID: nil, status: .completed),
        Appointment(id: therapySessionID, kind: .therapy, scheduledAt: date(1_788_382_800), startedAt: date(1_788_382_800), endedAt: date(1_788_385_920), providerID: uuid("31000000-0000-0000-0000-000000000001"), providerName: therapyProviderName, recordingAttachmentID: uuid("32000000-0000-0000-0000-000000000001"), transcriptID: uuid("32000000-0000-0000-0000-000000000002"), summaryID: uuid("32000000-0000-0000-0000-000000000003"), status: .completed, manualNotes: "We talked about the missed chance to prove I could have played. Dr. Park asked me to keep noticing when guilt appears after I feel better and to finish the senior-year football timeline. Exercise has helped when the thoughts feel stuck."),
    ]

    static let goals: [Goal] = [
        Goal(id: uuid("40000000-0000-0000-0000-000000000001"), title: "Notice when moving-forward guilt appears", detail: nil, cadence: .daily, source: .userExplicit, sourceEntityID: footballJournalID, sourceTimestampMilliseconds: nil, status: .active, createdAt: date(1_788_646_680), targetDate: date(1_788_654_600), provenance: provenance(.user, "You chose this", "Journal, Sep 5 at 3:18 PM", 1_788_646_680, .journalDetail)),
        Goal(id: uuid("40000000-0000-0000-0000-000000000002"), title: "Write down one example if guilt shows up", detail: nil, cadence: .weekly, source: .aiSuggested, sourceEntityID: footballJournalID, sourceTimestampMilliseconds: nil, status: .active, createdAt: date(1_788_646_800), targetDate: date(1_788_987_600), provenance: provenance(.candyCorn, "Candy Corn suggested this", "Based on your Sep 5 journal. You added it.", 1_788_646_800, .journalSuggestions)),
        Goal(id: uuid("40000000-0000-0000-0000-000000000003"), title: "Finish the senior-year football timeline", detail: nil, cadence: .homework, source: .providerExplicit, sourceEntityID: therapySessionID, sourceTimestampMilliseconds: 2_538_000, status: .completed, createdAt: date(1_788_385_338), targetDate: nil, provenance: provenance(.provider, "Therapist assigned this", "Therapy, Sep 2 at 42:18", 1_788_385_338, .therapySession)),
        Goal(id: uuid("40000000-0000-0000-0000-000000000004"), title: "Use exercise when thoughts feel stuck", detail: nil, cadence: .ongoing, source: .userExplicit, sourceEntityID: timelineJournalID, sourceTimestampMilliseconds: nil, status: .active, createdAt: date(1_788_476_760), targetDate: nil, provenance: provenance(.user, "You chose this", "Journal, Sep 3 at 4:06 PM", 1_788_476_760, .journalDetail)),
    ]

    static let talkingPoints: [TalkingPoint] = [
        TalkingPoint(id: uuid("50000000-0000-0000-0000-000000000001"), text: "Is needing proof that I could have played the part that keeps me stuck?", source: .journal, sourceID: footballJournalID, targetAppointmentKind: .therapy, isImportant: true, status: .open, createdAt: date(1_788_646_680), provenance: provenance(.user, "You pinned this", "Journal, Sep 5 at 3:18 PM", 1_788_646_680, .journalDetail)),
        TalkingPoint(id: uuid("50000000-0000-0000-0000-000000000002"), text: "Why does moving forward sometimes feel like dismissing what happened?", source: .aiSuggestion, sourceID: footballJournalID, targetAppointmentKind: .therapy, isImportant: false, status: .open, createdAt: date(1_788_646_800), provenance: provenance(.candyCorn, "Candy Corn suggested this", "Based on two journal entries. You added it.", 1_788_646_800, .journalSuggestions)),
        TalkingPoint(id: uuid("50000000-0000-0000-0000-000000000003"), text: "The senior-year meeting with the coaches", source: .session, sourceID: therapySessionID, targetAppointmentKind: .therapy, isImportant: false, status: .open, createdAt: date(1_788_385_124), provenance: provenance(.provider, "Therapist asked to revisit this", "Therapy, Sep 2 at 38:44", 1_788_385_124, .therapySession)),
    ]

    static let transcript: [TranscriptSegment] = [
        TranscriptSegment(id: uuid("60000000-0000-0000-0000-000000000001"), appointmentID: therapySessionID, speaker: .patient, rawSpeakerLabel: "Speaker 1", startMilliseconds: 744_000, endMilliseconds: 756_000, text: "I do not think I miss playing as much as I miss having the chance to prove I could have done it.", confidence: 0.96),
        TranscriptSegment(id: uuid("60000000-0000-0000-0000-000000000002"), appointmentID: therapySessionID, speaker: .provider, rawSpeakerLabel: "Speaker 2", startMilliseconds: 768_000, endMilliseconds: 781_000, text: "So the part that still hurts may be not getting to test what you believed about yourself.", confidence: 0.94),
        TranscriptSegment(id: uuid("60000000-0000-0000-0000-000000000003"), appointmentID: therapySessionID, speaker: .unknown, rawSpeakerLabel: "Speaker 1", startMilliseconds: 2_324_000, endMilliseconds: 2_331_000, text: "Let us make sure we come back to the meeting with the coaches.", confidence: nil),
    ]

    static let aiArtifacts: [AIArtifact] = [
        artifact("70000000-0000-0000-0000-000000000001", .journalRewrite, [footballJournalID], rewriteResult),
        artifact("70000000-0000-0000-0000-000000000002", .sessionSummary, [therapySessionID], sessionSummaryResult),
        artifact("70000000-0000-0000-0000-000000000003", .appointmentBrief, [footballJournalID, timelineJournalID, therapySessionID], appointmentBriefResult),
        artifact("70000000-0000-0000-0000-000000000004", .journalSignals, [footballJournalID], journalSignalResult),
    ]

    static let attachments: [Attachment] = [
        Attachment(
            id: uuid("11000000-0000-0000-0000-000000000001"),
            kind: .audio,
            relativePath: "audio/sample-football.m4a",
            mediaType: "audio/mp4",
            byteCount: 1_024,
            durationMilliseconds: 137_000,
            createdAt: date(1_788_646_680),
            isSample: true
        ),
        Attachment(
            id: uuid("32000000-0000-0000-0000-000000000001"),
            kind: .audio,
            relativePath: "audio/sample-therapy.m4a",
            mediaType: "audio/mp4",
            byteCount: 2_048,
            durationMilliseconds: 3_120_000,
            createdAt: date(1_788_382_800),
            isSample: true
        ),
    ]

    static let providers: [ProviderProfile] = [
        ProviderProfile(id: uuid("31000000-0000-0000-0000-000000000001"), name: therapyProviderName, appointmentKind: .therapy, isSample: true),
        ProviderProfile(id: uuid("31000000-0000-0000-0000-000000000002"), name: tmsProviderName, appointmentKind: .tms, isSample: true),
    ]

    static var careSnapshot: CareSnapshot {
        CareSnapshot(
            journals: journalEntries,
            moods: moodLogs,
            appointments: appointments,
            goals: goals,
            goalProgress: [],
            talkingPoints: talkingPoints,
            artifacts: aiArtifacts,
            attachments: attachments,
            providers: providers,
            transcript: transcript,
            settings: VaultSettings(useSampleContent: true, audioRetention: .ask, aiMode: .off, aiProvider: .off)
        )
    }

    static var emptySnapshot: CareSnapshot {
        CareSnapshot(
            journals: [], moods: [], appointments: [], goals: [], goalProgress: [],
            talkingPoints: [], artifacts: [], attachments: [], providers: [], transcript: [],
            settings: VaultSettings(useSampleContent: false, audioRetention: .ask, aiMode: .off, aiProvider: .off)
        )
    }

    private static func uuid(_ value: String) -> UUID {
        guard let id = UUID(uuidString: value) else { preconditionFailure("Seed UUID must be valid") }
        return id
    }

    private static func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    private static func provenance(_ voice: ProvenanceVoice, _ label: String, _ detail: String, _ seconds: TimeInterval, _ route: Route) -> Provenance {
        Provenance(voice: voice, label: label, detail: detail, occurredAt: date(seconds), sourceRoute: route)
    }

    private static let resultMetadata = AIResultMetadata(
        provider: "openrouter",
        model: AIModelConfiguration.defaults.organizerModelID,
        usage: AIUsage(promptTokens: 364, completionTokens: 182, reasoningTokens: 96, totalTokens: 642, costCredits: 0.00013)
    )

    private static let rewriteResult = RewriteJournalResult(
        segments: [
            RewriteSegment(
                id: uuid("71000000-0000-0000-0000-000000000001"),
                text: "Work felt steady until thoughts about football returned around three and brought up anger.",
                evidence: [citation(footballJournalID, "Work was fine until around three when I started thinking about football again. I got angry")]
            ),
            RewriteSegment(
                id: uuid("71000000-0000-0000-0000-000000000002"),
                text: "The gym helped for a few hours, followed by guilt when the football thoughts had been absent.",
                evidence: [citation(footballJournalID, "went to the gym, and felt better. Then I realized I had not thought about it for a few hours, and I felt guilty about that.")]
            ),
        ],
        unclearAreas: ["The entry does not say what the guilt means to Jamie."],
        metadata: resultMetadata
    )

    private static let journalSignalResult = JournalSignalResult(
        signals: JournalSignals(
            summary: "Football thoughts interrupted work, exercise helped, and guilt followed the relief.",
            emotions: [
                JournalSignals.EvidenceItem(label: "Anger", evidence: "I got angry"),
                JournalSignals.EvidenceItem(label: "Guilt", evidence: "I felt guilty about that"),
            ],
            explicitCommitments: [],
            talkingPointSuggestions: [
                JournalSignals.TalkingPointSuggestion(
                    id: uuid("72000000-0000-0000-0000-000000000001"),
                    text: "Explore why relief from football thoughts was followed by guilt.",
                    reason: "The shift from feeling better to guilt may be useful to discuss without assuming its cause.",
                    evidence: "Then I realized I had not thought about it for a few hours, and I felt guilty about that."
                ),
            ],
            possibleThemes: [
                JournalSignals.EvidenceItem(label: "Exercise and relief", evidence: "went to the gym, and felt better"),
            ]
        ),
        metadata: resultMetadata
    )

    private static let sessionSummaryResult = SessionSummaryResult(
        sections: [
            SessionSummarySection(
                id: uuid("73000000-0000-0000-0000-000000000001"),
                title: "What came up",
                statements: [statement("73100000-0000-0000-0000-000000000001",
                    "The missed chance to prove football ability remained important.",
                    therapySessionID,
                    "We talked about the missed chance to prove I could have played."
                )]
            ),
            SessionSummarySection(
                id: uuid("73000000-0000-0000-0000-000000000002"),
                title: "Homework",
                statements: [statement("73100000-0000-0000-0000-000000000002",
                    "Keep noticing guilt after feeling better and finish the senior-year football timeline.",
                    therapySessionID,
                    "Dr. Park asked me to keep noticing when guilt appears after I feel better and to finish the senior-year football timeline."
                )]
            ),
        ],
        metadata: resultMetadata
    )

    private static let appointmentBriefResult = AppointmentBriefResult(
        sections: [
            AppointmentBriefSection(
                id: uuid("74000000-0000-0000-0000-000000000001"),
                title: "What has been happening",
                statements: [statement("74100000-0000-0000-0000-000000000001",
                    "Exercise helped with football thoughts, then guilt appeared after a few hours of relief.",
                    footballJournalID,
                    "I got angry, went to the gym, and felt better. Then I realized I had not thought about it for a few hours, and I felt guilty about that."
                )]
            ),
            AppointmentBriefSection(
                id: uuid("74000000-0000-0000-0000-000000000002"),
                title: "What to revisit",
                statements: [
                    statement("74100000-0000-0000-0000-000000000002",
                        "The missed chance to prove football ability still feels unresolved.",
                        timelineJournalID,
                        "What still bothers me is never getting the chance to prove I could have played."
                    ),
                    statement("74100000-0000-0000-0000-000000000003",
                        "The therapy homework was to notice guilt and finish the senior-year timeline.",
                        therapySessionID,
                        "Dr. Park asked me to keep noticing when guilt appears after I feel better and to finish the senior-year football timeline."
                    ),
                ]
            ),
        ],
        userEditedAt: nil,
        metadata: resultMetadata
    )

    private static func citation(_ sourceID: UUID, _ quote: String) -> EvidenceCitation {
        EvidenceCitation(sourceID: sourceID, quote: quote, timestampMilliseconds: nil)
    }

    private static func statement(_ id: String, _ text: String, _ sourceID: UUID, _ quote: String) -> EvidenceBackedStatement {
        EvidenceBackedStatement(id: uuid(id), text: text, evidence: [citation(sourceID, quote)])
    }

    private static func artifact<Payload: Encodable>(_ id: String, _ kind: AIArtifact.Kind, _ sourceIDs: [UUID], _ payload: Payload) -> AIArtifact {
        AIArtifact(
            id: uuid(id),
            kind: kind,
            sourceIDs: sourceIDs,
            provider: resultMetadata.provider,
            model: resultMetadata.model,
            structuredPayload: encoded(payload),
            createdAt: date(1_788_646_920)
        )
    }

    private static func encoded<Payload: Encodable>(_ payload: Payload) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        do {
            return try encoder.encode(payload)
        } catch {
            preconditionFailure("Seed AI payload must encode")
        }
    }
}
