import Foundation
import Testing
@testable import CandyCorn

@Suite("AI consent surfaces")
struct AIConsentSurfaceTests {
    private let configuration = AIModelConfiguration(
        organizerModelID: "organizer-model",
        visionModelID: "vision-model"
    )

    @Test("Disclosure formats exact character and image counts")
    func sourceCountFormatting() {
        let photo = source(title: "Original journal photo", characters: 0, images: 1)
        let journal = source(title: "Football and feeling guilty", characters: 184, images: 0)
        let mixed = source(title: "Page and note", characters: 1, images: 2)

        #expect(AISendDisclosureText.sourceCounts(photo) == "0 characters · 1 image")
        #expect(AISendDisclosureText.sourceCounts(journal) == "184 characters")
        #expect(AISendDisclosureText.sourceCounts(mixed) == "1 character · 2 images")
        #expect(AISendDisclosureText.sourceAccessibilityLabel(photo) == "Original journal photo. 0 characters · 1 image")
        #expect(AISendDisclosureText.sendActionName == "Send")
        #expect(AISendDisclosureText.cancelActionName == "Cancel")
    }

    @Test("Disclosure reports only nonzero omitted sources")
    func omittedSourceFormatting() {
        #expect(AISendDisclosureText.omittedSources(0) == nil)
        #expect(AISendDisclosureText.omittedSources(1) == "1 newer journal was not included.")
        #expect(AISendDisclosureText.omittedSources(3) == "3 newer journals were not included.")
    }

    @Test("Router status names configured cloud models")
    func configuredRouterStatus() {
        let rows = AIProcessingStatusLogic.rows(
            mode: .organizer,
            provider: .router,
            hasOpenRouterKey: true,
            configuration: configuration
        )

        #expect(rows.count == 4)
        #expect(rows[0].detail == "Cloud (router, organizer-model)")
        #expect(rows[1].detail == "Not yet available")
        #expect(rows[2].detail == "Cloud (router, vision-model)")
        #expect(rows[3].detail == "Only when you tap Send")
    }

    @Test("Router without a key is unavailable")
    func missingRouterKeyStatus() {
        let rows = AIProcessingStatusLogic.rows(
            mode: .organizer,
            provider: .router,
            hasOpenRouterKey: false,
            configuration: configuration
        )

        #expect(rows[0].detail == "Unavailable until you add a router key")
        #expect(rows[2].detail == "Unavailable until you add a router key")
        #expect(rows[1].detail == "Not yet available")
    }

    @Test("AI Off is truthful while upload remains user initiated")
    func offStatus() {
        let rows = AIProcessingStatusLogic.rows(
            mode: .off,
            provider: .router,
            hasOpenRouterKey: true,
            configuration: configuration
        )

        #expect(rows[0].detail == "Off")
        #expect(rows[2].detail == "Off")
        #expect(rows[1].accessibilityLabel == "Voice transcription. Not yet available")
        #expect(rows[3].detail == "Only when you tap Send")
    }

    @Test("Reflection uses Organizer processing status")
    func reflectionStatus() {
        let organizer = AIProcessingStatusLogic.rows(
            mode: .organizer,
            provider: .router,
            hasOpenRouterKey: true,
            configuration: configuration
        )
        let reflection = AIProcessingStatusLogic.rows(
            mode: .reflection,
            provider: .router,
            hasOpenRouterKey: true,
            configuration: configuration
        )

        #expect(reflection == organizer)
        #expect(reflection[1].detail == "Not yet available")
    }

    @Test("Operation states retain concrete labels")
    func processingStateLabels() {
        #expect(AIProcessingStatePresentation.make(for: .idle) == nil)
        #expect(AIProcessingStatePresentation.make(for: .processing)?.title == "Sending to Candy Corn")
        #expect(AIProcessingStatePresentation.make(for: .succeeded)?.detail == "Your original source is unchanged.")
        #expect(AIProcessingStatePresentation.make(for: .failed("Try again."))?.detail == "Try again.")
    }

    private func source(title: String, characters: Int, images: Int) -> OutgoingSourceDescriptor {
        OutgoingSourceDescriptor(
            id: UUID(),
            kind: images > 0 ? .image : .text,
            title: title,
            characterCount: characters,
            imageCount: images
        )
    }
}
