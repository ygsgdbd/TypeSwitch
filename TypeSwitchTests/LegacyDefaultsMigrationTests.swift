import Foundation
@testable import TypeSwitch
import XCTest

final class LegacyDefaultsMigrationTests: XCTestCase {
    func testV2CompletionIgnoresLegacyBooleanMarker() throws {
        let suiteName = "LegacyDefaultsMigrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: "didMigrateLegacyAppRules")

        XCTAssertEqual(LegacyDefaultsMigration.completedVersion(in: defaults), 0)
    }

    func testMakeRulesPreservesMatchedAndUnavailableApplications() {
        let migrationDate = Date(timeIntervalSince1970: 777)
        let matchedApplications = [
            "com.test.notes": AppInfo(
                bundleId: "com.test.notes",
                name: "Notes",
                path: "/Applications/Notes.app"
            ),
        ]

        let rules = LegacyDefaultsMigration.makeRules(
            legacyMappings: [
                "com.test.notes": "ime.zh",
                "com.test.missing": "ime.en",
            ],
            matchedApplications: matchedApplications,
            migrationDate: migrationDate
        )

        XCTAssertEqual(
            rules,
            [
                "com.test.notes": AppRuleRecord(
                    bundleId: "com.test.notes",
                    lastKnownPath: "/Applications/Notes.app",
                    lastKnownName: "Notes",
                    strategy: .fixed(inputMethodId: "ime.zh"),
                    createdAt: migrationDate,
                    updatedAt: migrationDate
                ),
                "com.test.missing": AppRuleRecord(
                    bundleId: "com.test.missing",
                    lastKnownPath: nil,
                    lastKnownName: "com.test.missing",
                    strategy: .fixed(inputMethodId: "ime.en"),
                    createdAt: migrationDate,
                    updatedAt: migrationDate
                ),
            ]
        )
    }
}
