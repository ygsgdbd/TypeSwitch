import ComposableArchitecture
import Foundation

// Migration: v0 -> v1
// Added: 2026-05-25
enum LegacyDefaultsMigration {
    static func makeRules(
        legacyMappings: [String: String],
        matchedApplications: [String: AppInfo],
        migrationDate: Date
    ) -> [String: AppRuleRecord] {
        legacyMappings.reduce(into: [String: AppRuleRecord]()) { result, entry in
            guard let appInfo = matchedApplications[entry.key] else {
                return
            }

            result[entry.key] = AppRuleRecord(
                bundleId: entry.key,
                lastKnownPath: appInfo.path,
                lastKnownName: appInfo.name,
                strategy: .fixed(inputMethodId: entry.value),
                createdAt: migrationDate,
                updatedAt: migrationDate
            )
        }
    }
}

struct LegacyDefaultsMigrationClient {
    var didCompleteMigration: @Sendable () async -> Bool
    var migrateRules: @Sendable (_ migrationDate: Date) async -> [String: AppRuleRecord]
}

extension LegacyDefaultsMigrationClient: DependencyKey {
    static let liveValue = Self(
        didCompleteMigration: {
            UserDefaults.standard.bool(forKey: "didMigrateLegacyAppRules")
        },
        migrateRules: { migrationDate in
            let defaults = UserDefaults(suiteName: "group.top.ygsgdbd.TypeSwitch") ?? .standard
            let legacyMappings = defaults.dictionary(forKey: "appInputMethodSettings")?
                .compactMapValues { $0 as? String } ?? [:]

            defer {
                UserDefaults.standard.set(true, forKey: "didMigrateLegacyAppRules")
            }

            guard !legacyMappings.isEmpty else {
                return [:]
            }

            let matchedApplications = await AppListService.fetchApps(matching: Set(legacyMappings.keys))
            return LegacyDefaultsMigration.makeRules(
                legacyMappings: legacyMappings,
                matchedApplications: matchedApplications,
                migrationDate: migrationDate
            )
        }
    )

    static let testValue = Self(
        didCompleteMigration: { true },
        migrateRules: { _ in [:] }
    )
}

extension DependencyValues {
    var legacyDefaultsMigrationClient: LegacyDefaultsMigrationClient {
        get { self[LegacyDefaultsMigrationClient.self] }
        set { self[LegacyDefaultsMigrationClient.self] = newValue }
    }
}
