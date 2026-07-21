import ComposableArchitecture
import Foundation

// Migration: legacy defaults -> app rules store
enum LegacyDefaultsMigration {
    static let currentVersion = 2
    static let versionKey = "legacyAppRulesMigrationVersion"

    static func completedVersion(in defaults: UserDefaults) -> Int {
        defaults.integer(forKey: versionKey)
    }

    static func makeRules(
        legacyMappings: [String: String],
        matchedApplications: [String: AppInfo],
        migrationDate: Date
    ) -> [String: AppRuleRecord] {
        legacyMappings.reduce(into: [String: AppRuleRecord]()) { result, entry in
            let appInfo = matchedApplications[entry.key]

            result[entry.key] = AppRuleRecord(
                bundleId: entry.key,
                lastKnownPath: appInfo?.path,
                lastKnownName: appInfo?.name ?? entry.key,
                strategy: .fixed(inputMethodId: entry.value),
                createdAt: migrationDate,
                updatedAt: migrationDate
            )
        }
    }
}

struct LegacyDefaultsMigrationClient {
    var completedVersion: @Sendable () async -> Int
    var loadRules: @Sendable (_ migrationDate: Date) async -> [String: AppRuleRecord]
    var markCompleted: @Sendable (_ version: Int) async -> Void
}

extension LegacyDefaultsMigrationClient: DependencyKey {
    static let liveValue = Self(
        completedVersion: {
            LegacyDefaultsMigration.completedVersion(in: .standard)
        },
        loadRules: { migrationDate in
            let defaults = UserDefaults(suiteName: "group.top.ygsgdbd.TypeSwitch") ?? .standard
            let legacyMappings = defaults.dictionary(forKey: "appInputMethodSettings")?
                .compactMapValues { $0 as? String } ?? [:]

            guard !legacyMappings.isEmpty else {
                return [:]
            }

            let matchedApplications = await AppListService.fetchApps(matching: Set(legacyMappings.keys))
            return LegacyDefaultsMigration.makeRules(
                legacyMappings: legacyMappings,
                matchedApplications: matchedApplications,
                migrationDate: migrationDate
            )
        },
        markCompleted: { version in
            UserDefaults.standard.set(version, forKey: LegacyDefaultsMigration.versionKey)
        }
    )

    static let testValue = Self(
        completedVersion: { LegacyDefaultsMigration.currentVersion },
        loadRules: { _ in [:] },
        markCompleted: { _ in }
    )
}

extension DependencyValues {
    var legacyDefaultsMigrationClient: LegacyDefaultsMigrationClient {
        get { self[LegacyDefaultsMigrationClient.self] }
        set { self[LegacyDefaultsMigrationClient.self] = newValue }
    }
}
