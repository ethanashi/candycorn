import Foundation
import Testing
@testable import CandyCorn

@Suite("AI settings feature")
struct AISettingsFeatureTests {
    @Test("Router eligibility requires a key and an enabled AI mode")
    func routerEligibility() {
        #expect(!AISettingsLogic.canSelectRouter(mode: .off, hasKey: false))
        #expect(!AISettingsLogic.canSelectRouter(mode: .off, hasKey: true))
        #expect(!AISettingsLogic.canSelectRouter(mode: .organizer, hasKey: false))
        #expect(AISettingsLogic.canSelectRouter(mode: .organizer, hasKey: true))
        #expect(AISettingsLogic.canSelectRouter(mode: .reflection, hasKey: true))
    }

    @MainActor
    @Test("Organizer enables Router only after a key is saved and removal turns Router off")
    func keyLifecycleControlsRouter() async throws {
        let dependencies = PreviewDependencies.make()
        try dependencies.openRouterKeyStore.removeKey()
        let state = DemoState(dependencies: dependencies, arguments: ["CandyCorn"])
        await state.load()

        #expect(!state.hasOpenRouterKey)
        AISettingsLogic.selectMode(.organizer, in: state)
        #expect(await state.updateSettings(state.settings))
        #expect(state.aiProvider == .off)
        #expect(!AISettingsLogic.canSelect(.router, in: state))

        #expect(state.storeOpenRouterKey("  fictional-test-key  "))
        #expect(state.hasOpenRouterKey)
        #expect(AISettingsLogic.canSelect(.router, in: state))
        #expect(await state.persistAIProvider(.router))
        #expect(state.aiProvider == .router)

        #expect(await state.removeOpenRouterKey())
        #expect(!state.hasOpenRouterKey)
        #expect(state.aiProvider == .off)
        #expect(!AISettingsLogic.canSelect(.router, in: state))
    }

    @MainActor
    @Test("Selecting Off forces the provider Off")
    func offForcesProviderOff() async {
        let state = DemoState(dependencies: PreviewDependencies.make(), arguments: ["CandyCorn"])
        await state.load()

        #expect(await state.persistAIMode(.organizer))
        #expect(await state.persistAIProvider(.router))
        #expect(state.aiProvider == .router)
        #expect(await state.persistAIMode(.off))
        #expect(state.aiProvider == .off)
    }

    @Test("Reflection explains its Organizer behavior without promising conversation")
    func reflectionPlaceholder() {
        #expect(AISettingsLogic.modeDescription(.reflection) == AISettingsLogic.reflectionNote)
        #expect(AISettingsLogic.reflectionNote == "Reflection uses Organizer for now. It does not start a conversation.")
    }

    @Test("Key input trims only surrounding whitespace and remains bounded")
    func keyValidation() throws {
        #expect(try AISettingsLogic.normalizedKey("  key with spaces inside  ") == "key with spaces inside")
        #expect(throws: AISettingsValidationError.emptyKey) {
            try AISettingsLogic.normalizedKey(" \n\t ")
        }
        #expect(throws: AISettingsValidationError.keyTooLong) {
            try AISettingsLogic.normalizedKey(
                String(repeating: "x", count: OpenRouterAPIKeyStore.maximumCharacterCount + 1)
            )
        }
    }

    @Test("Model validation trims both fields and rejects blank or oversized IDs")
    func modelValidation() throws {
        let configuration = try AISettingsLogic.validatedConfiguration(
            organizerModelID: "  provider/organizer  ",
            visionModelID: "\nprovider/vision\t"
        )
        #expect(configuration.organizerModelID == "provider/organizer")
        #expect(configuration.visionModelID == "provider/vision")
        #expect(throws: AISettingsValidationError.emptyOrganizerModel) {
            try AISettingsLogic.validatedConfiguration(organizerModelID: " ", visionModelID: "provider/vision")
        }
        #expect(throws: AISettingsValidationError.emptyVisionModel) {
            try AISettingsLogic.validatedConfiguration(organizerModelID: "provider/organizer", visionModelID: " ")
        }
        #expect(throws: AISettingsValidationError.visionModelTooLong) {
            try AISettingsLogic.validatedConfiguration(
                organizerModelID: "provider/organizer",
                visionModelID: String(
                    repeating: "v",
                    count: UserDefaultsAIConfigurationStore.maximumModelIdentifierCount + 1
                )
            )
        }
    }

    @MainActor
    @Test("Model settings save together and restore the documented defaults")
    func modelSaveAndRestore() {
        let state = DemoState(dependencies: PreviewDependencies.make(), arguments: ["CandyCorn"])
        let custom = AIModelConfiguration(
            organizerModelID: "provider/custom-organizer",
            visionModelID: "provider/custom-vision"
        )

        #expect(state.updateAIConfiguration(custom))
        #expect(state.aiConfiguration == custom)
        #expect(state.updateAIConfiguration(.defaults))
        #expect(state.aiConfiguration == .defaults)
    }

    @Test("Processing ledger stays truthful for enabled, missing-key, Off, and future providers")
    func statusRows() {
        let configuration = AIModelConfiguration(
            organizerModelID: "organizer-model",
            visionModelID: "vision-model"
        )
        let enabled = AIProcessingStatusLogic.rows(
            mode: .organizer,
            provider: .router,
            hasOpenRouterKey: true,
            configuration: configuration
        )
        let missingKey = AIProcessingStatusLogic.rows(
            mode: .organizer,
            provider: .router,
            hasOpenRouterKey: false,
            configuration: configuration
        )
        let off = AIProcessingStatusLogic.rows(
            mode: .off,
            provider: .router,
            hasOpenRouterKey: true,
            configuration: configuration
        )
        let onDevice = AIProcessingStatusLogic.rows(
            mode: .organizer,
            provider: .onDeviceWhenAvailable,
            hasOpenRouterKey: true,
            configuration: configuration
        )

        #expect(enabled.map(\.detail) == [
            "Cloud (router, organizer-model)",
            "Not yet available",
            "Cloud (router, vision-model)",
            "Only when you tap Send",
        ])
        #expect(missingKey[0].detail == "Unavailable until you add a router key")
        #expect(missingKey[2].detail == "Unavailable until you add a router key")
        #expect(off[0].detail == "Off")
        #expect(off[2].detail == "Off")
        #expect(onDevice[0].detail == "Not yet available")
        #expect(onDevice[2].detail == "Not yet available")
    }
}
