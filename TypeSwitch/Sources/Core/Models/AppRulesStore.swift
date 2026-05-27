import Foundation

struct AppRulesStore: Codable, Hashable, Sendable {
    var v: Int
    var rules: [String: AppRuleRecord]

    init(v: Int = MigrationVersion.current, rules: [String: AppRuleRecord] = [:]) {
        self.v = v
        self.rules = rules
    }
}

struct FallbackRuleStore: Codable, Hashable, Sendable {
    var v: Int
    var strategy: InputMethodStrategy

    init(v: Int = MigrationVersion.current, strategy: InputMethodStrategy = .none) {
        self.v = v
        self.strategy = strategy
    }
}
