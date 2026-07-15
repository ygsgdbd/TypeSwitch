import Foundation
@testable import TypeSwitch
import XCTest

final class LegacyDefaultsMigrationTests: XCTestCase {
    func testMakeRulesMigratesOnlyMatchedApplications() {
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
            ]
        )
    }
}
