import ComposableArchitecture
import Sharing

enum AppRulesStoreMigration {
    static func merge(
        currentRules: [String: AppRuleRecord],
        legacyRules: [String: AppRuleRecord],
        didCompleteLegacyMigration: Bool
    ) -> [String: AppRuleRecord] {
        guard !didCompleteLegacyMigration || currentRules.isEmpty else {
            return currentRules
        }

        return legacyRules.reduce(into: currentRules) { rules, entry in
            guard let currentRule = rules[entry.key] else {
                rules[entry.key] = entry.value
                return
            }

            guard currentRule.strategy == .none,
                  currentRule.createdAt == currentRule.updatedAt
            else {
                return
            }

            var recoveredRule = currentRule
            recoveredRule.strategy = entry.value.strategy
            recoveredRule.updatedAt = entry.value.updatedAt
            if recoveredRule.lastKnownPath == nil {
                recoveredRule.lastKnownPath = entry.value.lastKnownPath
            }
            if recoveredRule.lastKnownName == recoveredRule.bundleId,
               entry.value.lastKnownName != entry.value.bundleId
            {
                recoveredRule.lastKnownName = entry.value.lastKnownName
            }
            rules[entry.key] = recoveredRule
        }
    }
}

struct AppRulesStoreMigrationClient {
    var save: @Sendable (_ store: Shared<AppRulesStore>) async throws -> Void
}

extension AppRulesStoreMigrationClient: DependencyKey {
    static let liveValue = Self(
        save: { store in
            try await store.save()
        }
    )

    static let testValue = Self(
        save: { _ in }
    )
}

extension DependencyValues {
    var appRulesStoreMigrationClient: AppRulesStoreMigrationClient {
        get { self[AppRulesStoreMigrationClient.self] }
        set { self[AppRulesStoreMigrationClient.self] = newValue }
    }
}
