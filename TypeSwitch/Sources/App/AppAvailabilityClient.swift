import Dependencies
import Foundation

/// Seeded at startup and replaced on each menu opening or before rule cleanup.
/// Keying by path prevents a rule's changed path from reusing its old result.
struct AppAvailabilitySnapshot: Equatable, Sendable {
    var availablePaths: Set<String> = []

    func availablePath(for rule: AppRuleRecord) -> String? {
        guard let path = rule.lastKnownPath, availablePaths.contains(path) else { return nil }
        return path
    }

    func isAvailable(_ rule: AppRuleRecord) -> Bool {
        availablePath(for: rule) != nil
    }

    func appInfo(for rule: AppRuleRecord) -> AppInfo {
        AppInfo(bundleId: rule.bundleId, name: rule.lastKnownName, path: availablePath(for: rule))
    }
}

struct AppAvailabilityClient: Sendable {
    var pathExists: @Sendable (String) -> Bool

    func snapshot(for rules: some Sequence<AppRuleRecord>) -> AppAvailabilitySnapshot {
        let paths = Set(rules.compactMap(\.lastKnownPath))
        return AppAvailabilitySnapshot(availablePaths: Set(paths.filter(pathExists)))
    }
}

extension AppAvailabilityClient: DependencyKey {
    static let liveValue = Self(pathExists: { FileManager.default.fileExists(atPath: $0) })
    static let testValue = Self(pathExists: { _ in false })
}

extension DependencyValues {
    var appAvailabilityClient: AppAvailabilityClient {
        get { self[AppAvailabilityClient.self] }
        set { self[AppAvailabilityClient.self] = newValue }
    }
}
