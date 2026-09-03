import Foundation
import Testing
@testable import CandyCorn

@Suite("Timestamp transcript alignment")
struct TranscriptAlignmentTests {
    private let appointmentID = UUID(uuidString: "91000000-0000-0000-0000-000000000001")!

    @Test("Bundled synthetic audio exercises fake adapters and stable alignment")
    func bundledFixture() async throws {
        let fixture = try #require(Bundle(for: FixtureBundleAnchor.self).url(
            forResource: "two-speaker-session",
            withExtension: "m4a"
        ))
        let values = try fixture.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        #expect(values.isRegularFile == true)
        #expect((values.fileSize ?? 0) > 1_000)

        let transcript = TranscriptResult(text: "First Second Third Fourth", segments: [
            piece("First", 800, 3_200), piece("Second", 4_000, 5_900),
            piece("Third", 6_700, 9_400), piece("Fourth", 10_200, 13_700),
        ])
        let diarization = result(
            [
                interval("speaker-0", 500, 3_500, 0.96), interval("speaker-1", 3_700, 6_200, 0.92),
                interval("speaker-0", 6_500, 9_700, 0.94), interval("speaker-1", 10_000, 14_000, 0.90),
            ],
            embeddings: [embedding("speaker-0", [1, 0]), embedding("speaker-1", [0, 1])]
        )
        let transcriber = FakeTranscriber(sessionResult: transcript)
        let diarizer = FakeDiarizer(result: diarization, progress: [.checkingModels, .processing(completed: 1, total: 1)])
        let recognized = try await transcriber.transcribeSession(audioURL: fixture)
        let separated = try await diarizer.diarize(audioURL: fixture) { _ in }
        let aligned = try makeAligner(count: 4).align(input(transcript: recognized, diarization: separated))

        #expect(aligned.map(\.rawSpeakerLabel) == ["speaker-0", "speaker-1", "speaker-0", "speaker-1"])
        #expect(aligned.map(\.speaker) == [.unknown, .unknown, .unknown, .unknown])
        #expect(aligned.map(\.text) == ["First", "Second", "Third", "Fourth"])
        #expect(aligned.map(\.startMilliseconds) == [800, 4_000, 6_700, 10_200])
        #expect(aligned.map(\.id) == Array(Self.ids.prefix(4)))
    }

    @Test("Greatest overlap, boundary fallback, and deterministic ties select clusters")
    func matchingRules() throws {
        let transcript = TranscriptResult(text: "tie boundary nearest label aggregate", segments: [
            piece("nearest", 3_000, 3_100), piece("tie", 1_000, 2_000), piece("boundary", 4_100, 4_200),
            piece("label", 7_000, 7_500), piece("aggregate", 8_000, 10_000),
        ])
        let diarization = result([
            interval("speaker-z", 1_500, 2_100, 0.8), interval("speaker-a", 900, 1_500, 0.9),
            interval("speaker-near", 2_500, 2_600, nil), interval("speaker-early", 3_500, 3_600, nil),
            interval("speaker-z", 6_900, 7_600, nil), interval("speaker-a", 6_900, 7_600, nil),
            interval("speaker-split", 8_000, 8_500, 0.8), interval("speaker-single", 8_500, 9_400, 0.9),
            interval("speaker-split", 9_500, 10_000, 1.0),
        ])

        let aligned = try makeAligner(count: 5).align(input(transcript: transcript, diarization: diarization))

        #expect(aligned.map(\.text) == ["tie", "nearest", "boundary", "label", "aggregate"])
        #expect(aligned.map(\.rawSpeakerLabel) == [
            "speaker-a", "speaker-near", "speaker-early", "speaker-a", "speaker-split",
        ])
    }

    @Test("A fallback gap beyond 500 milliseconds is rejected")
    func fallbackLimit() {
        let transcript = TranscriptResult(text: "Too far", segments: [piece("Too far", 1_001, 1_500)])
        let diarization = result([interval("speaker-0", 0, 500, nil)])
        #expect(throws: TranscriptAlignmentError.unmatchedTranscriptPiece(pieceIndex: 0)) {
            _ = try makeAligner(count: 1).align(input(transcript: transcript, diarization: diarization))
        }
    }

    @Test("Adjacent matching pieces coalesce with source order and weighted confidence")
    func coalescing() throws {
        let transcript = TranscriptResult(text: "One two three four", segments: [
            piece("three", 3_400, 3_900), piece("One", 100, 1_100),
            piece("two", 2_300, 3_300), piece("four", 5_101, 5_601),
        ])
        let diarization = result([
            interval("speaker-0", 0, 2_000, 1.0), interval("speaker-0", 2_000, 4_000, 0.5),
            interval("speaker-0", 5_000, 6_000, nil),
        ])

        let aligned = try makeAligner(count: 2).align(input(transcript: transcript, diarization: diarization))

        #expect(aligned.count == 2)
        #expect(aligned[0].text == "One two three")
        #expect(aligned[0].startMilliseconds == 100)
        #expect(aligned[0].endMilliseconds == 3_900)
        #expect(abs((aligned[0].confidence ?? 0) - 0.7) < 0.000_001)
        #expect(aligned[1].text == "four")
        #expect(aligned[1].confidence == nil)
    }

    @Test("Explicit assignments win and are appointment scoped")
    func explicitAssignments() throws {
        let transcript = TranscriptResult(text: "Both", segments: [piece("Both", 100, 900)])
        let diarization = result(
            [interval("speaker-0", 0, 1_000, 0.9)],
            embeddings: [embedding("speaker-0", [1, 0])]
        )
        let assignments = [
            assignment(appointmentID: UUID(), label: "speaker-0", speaker: .patient),
            assignment(appointmentID: appointmentID, label: "speaker-0", speaker: .provider),
        ]
        let profiles = [profile([1, 0])]

        let aligned = try makeAligner(count: 1).align(input(
            transcript: transcript, diarization: diarization, assignments: assignments, profiles: profiles
        ))

        #expect(aligned.first?.speaker == .provider)
    }

    @Test("A strong model-compatible profile labels only its clear cluster as patient")
    func strongPatientProfile() throws {
        let aligned = try profileAlignment(
            embeddings: [embedding("speaker-0", [1, 0]), embedding("speaker-1", [0, 1])],
            profiles: [profile([1, 0])]
        )
        #expect(aligned.map(\.speaker) == [.patient, .unknown])
    }

    @Test("Ambiguous and malformed biometrics never infer a patient or provider")
    func ambiguousAndMalformedProfiles() throws {
        let ambiguous = try profileAlignment(
            embeddings: [embedding("speaker-0", [1, 0]), embedding("speaker-1", [0.96, 0.28])],
            profiles: [profile([1, 0])]
        )
        let malformed = try profileAlignment(
            embeddings: [
                embedding("speaker-0", [.nan, 0]), embedding("speaker-1", [0]),
                SpeakerEmbedding(rawSpeakerLabel: "speaker-1", modelID: "other-model", values: [1, 0]),
            ],
            profiles: [profile([0, 0]), profile([1, 0, 0])]
        )
        #expect(ambiguous.map(\.speaker) == [.unknown, .unknown])
        #expect(malformed.map(\.speaker) == [.unknown, .unknown])
    }

    @Test("Two unlabeled clusters remain unknown regardless of early speaking duration")
    func unlabeledTwoClusterSession() throws {
        let transcript = TranscriptResult(text: "Long short", segments: [
            piece("Long", 0, 20_000), piece("short", 21_000, 22_000),
        ])
        let diarization = result([
            interval("dominant-early", 0, 20_000, 0.9), interval("other", 21_000, 22_000, 0.9),
        ])
        let aligned = try makeAligner(count: 2).align(input(transcript: transcript, diarization: diarization))
        #expect(aligned.map(\.speaker) == [.unknown, .unknown])
        #expect(aligned.map(\.rawSpeakerLabel) == ["dominant-early", "other"])
    }

    @Test("Duplicate pieces preserve text and consume IDs in output order")
    func duplicatePieces() throws {
        let duplicate = piece("same source", 100, 200)
        let transcript = TranscriptResult(text: "same source same source", segments: [duplicate, duplicate])
        let diarization = result([interval("speaker-0", 0, 300, 0.7)])
        let aligned = try makeAligner(count: 1).align(input(transcript: transcript, diarization: diarization))
        #expect(aligned.count == 1)
        #expect(aligned[0].text == "same source same source")
        #expect(aligned[0].id == Self.ids[0])
    }

    @Test("Missing, invalid, empty, and whitespace transcript input is rejected")
    func invalidTranscriptInput() {
        let diarization = result([interval("speaker-0", 0, 1_000, nil)])
        let cases: [(TranscriptResult, TranscriptAlignmentError)] = [
            (TranscriptResult(text: "", segments: []), .emptyTranscript),
            (TranscriptResult(text: "missing", segments: [TranscriptPiece(text: "missing", startMilliseconds: nil, endMilliseconds: 1)]), .missingTimestamp(pieceIndex: 0)),
            (TranscriptResult(text: "negative", segments: [piece("negative", -1, 1)]), .invalidTranscriptRange(pieceIndex: 0)),
            (TranscriptResult(text: "zero", segments: [piece("zero", 1, 1)]), .invalidTranscriptRange(pieceIndex: 0)),
            (TranscriptResult(text: "space", segments: [piece(" \n", 0, 1)]), .emptyTranscriptText(pieceIndex: 0)),
        ]
        for (transcript, expected) in cases {
            #expect(throws: expected) {
                _ = try makeAligner(count: 1).align(input(transcript: transcript, diarization: diarization))
            }
        }
    }

    @Test("Malformed and empty diarization input is rejected")
    func invalidDiarizationInput() {
        let transcript = TranscriptResult(text: "valid", segments: [piece("valid", 0, 100)])
        let cases: [(DiarizationResult, TranscriptAlignmentError)] = [
            (result([]), .emptyDiarization),
            (result([interval("speaker", -1, 100, nil)]), .invalidDiarizationRange(intervalIndex: 0)),
            (result([interval("speaker", 100, 100, nil)]), .invalidDiarizationRange(intervalIndex: 0)),
            (result([interval(" ", 0, 100, nil)]), .invalidSpeakerLabel(intervalIndex: 0)),
            (result([interval("speaker", 0, 100, .nan)]), .invalidConfidence(intervalIndex: 0)),
        ]
        for (diarization, expected) in cases {
            #expect(throws: expected) {
                _ = try makeAligner(count: 1).align(input(transcript: transcript, diarization: diarization))
            }
        }
    }

    private func profileAlignment(
        embeddings: [SpeakerEmbedding],
        profiles: [PatientVoiceProfile]
    ) throws -> [TranscriptSegment] {
        let transcript = TranscriptResult(text: "A B", segments: [piece("A", 0, 400), piece("B", 2_000, 2_400)])
        let diarization = result(
            [interval("speaker-0", 0, 500, 0.9), interval("speaker-1", 2_000, 2_500, 0.9)],
            embeddings: embeddings
        )
        return try makeAligner(count: 2).align(input(transcript: transcript, diarization: diarization, profiles: profiles))
    }

    private func input(
        transcript: TranscriptResult,
        diarization: DiarizationResult,
        assignments: [SpeakerClusterAssignment] = [],
        profiles: [PatientVoiceProfile] = []
    ) -> TranscriptAlignmentInput {
        TranscriptAlignmentInput(
            appointmentID: appointmentID,
            transcript: transcript,
            diarization: diarization,
            assignments: assignments,
            patientVoiceProfiles: profiles
        )
    }

    private func makeAligner(count: Int) -> TimestampTranscriptAligner {
        precondition(count > 0 && count <= Self.ids.count)
        let sequence = LockedIDSequence(Array(Self.ids.prefix(count)))
        return TimestampTranscriptAligner { sequence.next() }
    }

    private func piece(_ text: String, _ start: Int, _ end: Int) -> TranscriptPiece {
        TranscriptPiece(text: text, startMilliseconds: start, endMilliseconds: end)
    }

    private func interval(_ label: String, _ start: Int, _ end: Int, _ confidence: Double?) -> DiarizationInterval {
        DiarizationInterval(rawSpeakerLabel: label, startMilliseconds: start, endMilliseconds: end, confidence: confidence)
    }

    private func result(
        _ intervals: [DiarizationInterval],
        embeddings: [SpeakerEmbedding] = []
    ) -> DiarizationResult {
        DiarizationResult(intervals: intervals, speakerEmbeddings: embeddings, modelID: "fixture-model")
    }

    private func embedding(_ label: String, _ values: [Float]) -> SpeakerEmbedding {
        SpeakerEmbedding(rawSpeakerLabel: label, modelID: "fixture-model", values: values)
    }

    private func profile(_ values: [Float]) -> PatientVoiceProfile {
        PatientVoiceProfile(id: UUID(), modelID: "fixture-model", embedding: values, createdAt: .distantPast)
    }

    private func assignment(
        appointmentID: UUID,
        label: String,
        speaker: TranscriptSegment.Speaker
    ) -> SpeakerClusterAssignment {
        SpeakerClusterAssignment(
            id: UUID(), appointmentID: appointmentID, rawSpeakerLabel: label,
            speaker: speaker, updatedAt: .distantPast
        )
    }

    private static let ids = (1...12).map { value in
        UUID(uuidString: String(format: "92000000-0000-0000-0000-%012d", value))!
    }
}

private final class FixtureBundleAnchor: NSObject {}

private final class LockedIDSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID]

    init(_ values: [UUID]) {
        precondition(!values.isEmpty && values.count <= 100)
        self.values = values
    }

    func next() -> UUID {
        lock.lock()
        defer { lock.unlock() }
        precondition(!values.isEmpty)
        return values.removeFirst()
    }
}
