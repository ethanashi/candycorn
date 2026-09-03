import Foundation
import Testing
@testable import CandyCorn

@Suite("Organizer output validation")
struct OrganizerValidationTests {
    private let validator = OrganizerOutputValidator()

    @Test("Uncertainty is preserved and certainty replacement is rejected")
    func uncertaintyFixture() throws {
        let source = document("I think he looked down at me but I don't remember.")
        let evidence = [citation(source, "I think he looked down at me but I don't remember.")]
        try validator.validateSummary([
            statement("I think he looked down at me, although I don't remember clearly.", evidence),
        ], sources: [source])
        #expect(throws: AIProviderError.invalidResponse) {
            try validator.validateSummary([statement("He looked down at me.", evidence)], sources: [source])
        }
    }

    @Test("Diagnosis insertion is rejected but source diagnosis language is retained")
    func diagnosisFixture() throws {
        let source = document("I kept thinking about the situation all night.")
        let evidence = [citation(source, source.text)]
        #expect(throws: AIProviderError.invalidResponse) {
            try validator.validateSummary([
                statement("My PTSD caused me to ruminate all night.", evidence),
            ], sources: [source])
        }
        try validator.validateSummary([
            statement("I kept thinking about the situation throughout the night.", evidence),
        ], sources: [source])

        let named = document("My clinician discussed PTSD with me.")
        try validator.validateSummary([
            statement("My clinician discussed PTSD with me.", [citation(named, named.text)]),
        ], sources: [named])
    }

    @Test("Motive invention is rejected")
    func motiveFixture() throws {
        let source = document("He smiled at me and it felt intimidating.")
        let evidence = [citation(source, source.text)]
        #expect(throws: AIProviderError.invalidResponse) {
            try validator.validateSummary([statement("He smiled to intimidate me.", evidence)], sources: [source])
        }
        try validator.validateSummary([
            statement("He smiled at me, and I experienced it as intimidating.", evidence),
        ], sources: [source])
    }

    @Test("Optional language is not promoted to an explicit commitment")
    func optionalCommitmentFixture() throws {
        let source = document("Maybe I should go outside more.")
        let signals = makeSignals(commitmentEvidence: source.text)
        #expect(throws: AIProviderError.invalidResponse) {
            try validator.validateSignals(signals, source: source)
        }
    }

    @Test("Explicit user and provider commitments retain exact evidence")
    func explicitCommitmentFixtures() throws {
        let user = document("I'm going to walk for 10 minutes tomorrow.")
        try validator.validateSignals(makeSignals(commitmentEvidence: user.text), source: user)

        let provider = document("This week I'd like you to write down when that thought appears.", kind: .homework)
        try validator.validateSignals(makeSignals(commitmentEvidence: provider.text), source: provider)
    }

    @Test("Fabricated evidence and unknown source ids reject the whole output")
    func fabricatedEvidence() {
        let source = document("I felt calmer after the gym.")
        #expect(throws: AIProviderError.invalidResponse) {
            try validator.validateSummary([
                statement("The gym helped.", [citation(source, "The gym fixed everything.")]),
            ], sources: [source])
        }
        let unknown = EvidenceCitation(sourceID: UUID(), quote: source.text, timestampMilliseconds: nil)
        #expect(throws: AIProviderError.invalidResponse) {
            try validator.validateSummary([statement("The gym helped.", [unknown])], sources: [source])
        }
    }

    @Test("No-op distress classification has no organizer side effects")
    func distressStub() async {
        let result = await NoOpDistressSupportClassifier().classify(.init(sourceID: UUID(), text: "Synthetic distress fixture"))
        #expect(result == DistressAssessment(level: .normal, evidenceSpans: [], uncertainty: 1, suggestedUI: .none))
    }

    private func document(_ text: String, kind: SourceTextDocument.Kind = .journal) -> SourceTextDocument {
        SourceTextDocument(id: UUID(), kind: kind, title: "Synthetic fixture", text: text, occurredAt: nil)
    }

    private func citation(_ source: SourceTextDocument, _ quote: String) -> EvidenceCitation {
        EvidenceCitation(sourceID: source.id, quote: quote, timestampMilliseconds: nil)
    }

    private func statement(_ text: String, _ evidence: [EvidenceCitation]) -> EvidenceBackedStatement {
        EvidenceBackedStatement(id: UUID(), text: text, evidence: evidence)
    }

    private func makeSignals(commitmentEvidence: String) -> JournalSignals {
        JournalSignals(
            summary: "A possible plan was mentioned.",
            emotions: [],
            explicitCommitments: [.init(
                id: UUID(), text: "Candidate action", cadenceHint: nil, evidence: commitmentEvidence
            )],
            talkingPointSuggestions: [],
            possibleThemes: []
        )
    }
}
