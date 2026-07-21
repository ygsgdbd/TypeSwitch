import ComposableArchitecture
import Sharing

enum AppRulesStoreMigration {
    static func merge(
        currentRules: [String: AppRuleRecord],
        legacyRules: [String: AppRuleRecord]
    ) -> [String: AppRuleRecord] {
        currentRules.merging(legacyRules) { currentRule, legacyRule in
            guard currentRule.strategy == .none else {
                return currentRule
            }

            var recoveredRule = currentRule
            if legacyRule.lastKnownPath != nil {
                recoveredRule.lastKnownPath = legacyRule.lastKnownPath
                recoveredRule.lastKnownName = legacyRule.lastKnownName
            }
            recoveredRule.strategy = legacyRule.strategy
            recoveredRule.updatedAt = legacyRule.updatedAt
            return recoveredRule
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
