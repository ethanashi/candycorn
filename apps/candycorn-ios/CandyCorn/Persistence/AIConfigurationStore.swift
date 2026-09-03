import Foundation

enum AIConfigurationStoreError: Error, Equatable, Sendable {
    case invalidModelIdentifier
    case encodingFailed
}

final class UserDefaultsAIConfigurationStore: AIConfigurationProviding, @unchecked Sendable {
    static let storageKey = "dev.candycorn.app.ai.model-configuration-v1"
    static let maximumModelIdentifierCount = 200

    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AIModelConfiguration {
        lock.withLock {
            guard let data = defaults.data(forKey: Self.storageKey),
                  let decoded = try? JSONDecoder().decode(AIModelConfiguration.self, from: data),
                  let normalized = try? Self.normalized(decoded) else {
                return .defaults
            }
            return normalized
        }
    }

    func save(_ configuration: AIModelConfiguration) throws {
        let normalized = try Self.normalized(configuration)
        let data: Data
        do {
            data = try JSONEncoder().encode(normalized)
        } catch {
            throw AIConfigurationStoreError.encodingFailed
        }
        lock.withLock { defaults.set(data, forKey: Self.storageKey) }
    }

    func reset() throws {
        lock.withLock { defaults.removeObject(forKey: Self.storageKey) }
    }

    private static func normalized(_ configuration: AIModelConfiguration) throws -> AIModelConfiguration {
        let organizer = configuration.organizerModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let vision = configuration.visionModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValid(organizer), isValid(vision) else {
            throw AIConfigurationStoreError.invalidModelIdentifier
        }
        return AIModelConfiguration(organizerModelID: organizer, visionModelID: vision)
    }

    private static func isValid(_ identifier: String) -> Bool {
        !identifier.isEmpty && identifier.count <= maximumModelIdentifierCount
    }
}
