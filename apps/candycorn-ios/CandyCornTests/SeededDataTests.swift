import Foundation
import Testing
@testable import CandyCorn

@Suite("Seeded data")
struct SeededDataTests {
    @Test("Fixture counts and identities are deterministic")
    func countsAndIdentities() {
        #expect(SeededData.patientName == "Jamie Rivera")
        #expect(SeededData.therapyProviderName == "Dr. Elena Park")
        #expect(SeededData.tmsProviderName == "Riverbend TMS team")
        #expect(SeededData.journalEntries.count == 2)
        #expect(SeededData.moodLogs.count == 1)
        #expect(SeededData.appointments.count == 3)
        #expect(SeededData.goals.count == 4)
        #expect(SeededData.talkingPoints.count == 3)
        #expect(SeededData.transcript.count == 3)
        #expect(SeededData.aiArtifacts.count == 3)

        let ids = SeededData.journalEntries.map(\.id)
            + SeededData.moodLogs.map(\.id)
            + SeededData.appointments.map(\.id)
            + SeededData.goals.map(\.id)
            + SeededData.talkingPoints.map(\.id)
            + SeededData.transcript.map(\.id)
            + SeededData.aiArtifacts.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("Mood and transcript values are valid")
    func ranges() {
        for mood in SeededData.moodLogs {
            for value in [mood.mood, mood.anxiety, mood.energy].compactMap({ $0 }) {
                #expect((1...10).contains(value))
            }
            for value in mood.customValues.values {
                #expect((1...10).contains(value))
            }
        }
        for segment in SeededData.transcript {
            #expect(segment.startMilliseconds >= 0)
            #expect(segment.endMilliseconds > segment.startMilliseconds)
            if let confidence = segment.confidence {
                #expect((0...1).contains(confidence))
            }
        }
    }

    @Test("Every relation and artifact source resolves")
    func relations() {
        let journalIDs = Set(SeededData.journalEntries.map(\.id))
        let appointmentIDs = Set(SeededData.appointments.map(\.id))
        let sourceIDs = journalIDs.union(appointmentIDs)
        #expect(SeededData.transcript.allSatisfy { appointmentIDs.contains($0.appointmentID) })
        #expect(SeededData.goals.compactMap(\.sourceEntityID).allSatisfy { sourceIDs.contains($0) })
        #expect(SeededData.talkingPoints.compactMap(\.sourceID).allSatisfy { sourceIDs.contains($0) })
        #expect(SeededData.aiArtifacts.flatMap(\.sourceIDs).allSatisfy { sourceIDs.contains($0) })
        #expect(SeededData.aiArtifacts.allSatisfy { !$0.provider.isEmpty && !$0.model.isEmpty && !$0.structuredPayload.isEmpty })
    }

    @Test("The fictional story preserves originals")
    func fictionalStory() {
        let football = SeededData.journalEntries.first { $0.id == SeededData.footballJournalID }
        #expect(football?.rawText.contains("football") == true)
        #expect(football?.rawText.contains("guilty") == true)
        #expect(football?.cleanedText != football?.rawText)
        #expect(SeededData.transcript.contains { $0.text.contains("chance to prove") })
        #expect(SeededData.goals.contains { $0.title.contains("senior-year football") })
    }
}
