import ComposableArchitecture
import Sharing

enum AppRulesStoreMigration {
    static func merge(
        currentRules: [String: AppRuleRecord],
        legacyRules: [String: AppRuleRecord]
    ) -> [String: AppRuleRecord] {
        currentRules.merging(legacyRules) { currentRule, legacyRule in
            currentRule.strategy == .none ? legacyRule : currentRule
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
