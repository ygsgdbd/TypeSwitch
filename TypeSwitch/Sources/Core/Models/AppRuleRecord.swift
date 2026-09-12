import Foundation

struct AppRuleRecord: Identifiable, Codable, Hashable, Sendable {
    let bundleId: String
    var lastKnownPath: String?
    var lastKnownName: String
    var strategy: InputMethodStrategy
    var strategyBeforeIgnoring: InputMethodStrategy? = nil
    var createdAt: Date
    var updatedAt: Date

    var id: String { bundleId }
}
