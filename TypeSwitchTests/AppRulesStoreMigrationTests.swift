import Foundation
@testable import TypeSwitch
import XCTest

final class AppRulesStoreMigrationTests: XCTestCase {
    func testAppRulesStoreEncodingIncludesVersion() throws {
        let store = AppRulesStore(
            v: MigrationVersion.current,
            rules: [
                "com.test.notes": AppRuleRecord(
                    bundleId: "com.test.notes",
                    lastKnownPath: "/Applications/Notes.app",
                    lastKnownName: "Notes",
                    strategy: .fixed(inputMethodId: "ime.zh"),
                    createdAt: Date(timeIntervalSince1970: 10),
                    updatedAt: Date(timeIntervalSince1970: 20)
                ),
            ]
        )

        let data = try JSONEncoder().encode(store)
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(payload["v"] as? Int, MigrationVersion.current)
        XCTAssertEqual(try JSONDecoder().decode(AppRulesStore.self, from: data), store)
    }

    func testAppRulesStoreRoundTripsIgnoredStrategy() throws {
        let store = AppRulesStore(
            rules: [
                "com.test.passwords": AppRuleRecord(
                    bundleId: "com.test.passwords",
                    lastKnownPath: "/Applications/Passwords.app",
                    lastKnownName: "Passwords",
                    strategy: .ignored,
                    createdAt: Date(timeIntervalSince1970: 10),
                    updatedAt: Date(timeIntervalSince1970: 20)
                ),
            ]
        )

        let data = try JSONEncoder().encode(store)

        XCTAssertEqual(try JSONDecoder().decode(AppRulesStore.self, from: data), store)
    }

    func testExistingInputMethodStrategiesStillDecode() throws {
        let decoder = JSONDecoder()

        XCTAssertEqual(
            try decoder.decode(InputMethodStrategy.self, from: Data(#"{"none":{}}"#.utf8)),
            .none
        )
        XCTAssertEqual(
            try decoder.decode(InputMethodStrategy.self, from: Data(#"{"fixed":{"inputMethodId":"ime.zh"}}"#.utf8)),
            .fixed(inputMethodId: "ime.zh")
        )
        XCTAssertEqual(
            try decoder.decode(InputMethodStrategy.self, from: Data(#"{"followLast":{"lastInputMethodId":"ime.jp"}}"#.utf8)),
            .followLast(lastInputMethodId: "ime.jp")
        )
    }

    func testFallbackRuleStoreDefaultsAndEncodingIncludeVersion() throws {
        let defaultStore = FallbackRuleStore()
        XCTAssertEqual(defaultStore.v, MigrationVersion.current)
        XCTAssertEqual(defaultStore.strategy, .none)

        let store = FallbackRuleStore(strategy: .fixed(inputMethodId: "ime.abc"))
        let data = try JSONEncoder().encode(store)
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(payload["v"] as? Int, MigrationVersion.current)
        XCTAssertEqual(try JSONDecoder().decode(FallbackRuleStore.self, from: data), store)
    }

    func testAppSwitchStatisticsStoreDefaultsAndEncoding() throws {
        let defaultStore = AppSwitchStatisticsStore()
        XCTAssertTrue(defaultStore.counts.isEmpty)

        let store = AppSwitchStatisticsStore(counts: [
            "com.test.notes": 2,
            "com.test.browser": 5,
        ])
        let data = try JSONEncoder().encode(store)

        XCTAssertEqual(try JSONDecoder().decode(AppSwitchStatisticsStore.self, from: data), store)
    }

    func testAppRulesStoreURLUsesBundleIdentifierDirectory() {
        let applicationSupportDirectory = URL(fileURLWithPath: "/tmp/Application Support", isDirectory: true)
        let url = URL.appRulesStoreFileURL(
            applicationSupportDirectory: applicationSupportDirectory,
            bundleIdentifier: "com.test.TypeSwitch"
        )

        XCTAssertEqual(
            url.path,
            applicationSupportDirectory
                .appending(path: "com.test.TypeSwitch", directoryHint: .isDirectory)
                .appending(path: AppStorageConfiguration.appRulesFilename)
                .path
        )
    }

    func testFallbackRuleStoreURLUsesFallbackRuleFilename() {
        let applicationSupportDirectory = URL(fileURLWithPath: "/tmp/Application Support", isDirectory: true)
        let url = URL.fallbackRuleStoreFileURL(
            applicationSupportDirectory: applicationSupportDirectory,
            bundleIdentifier: "com.test.TypeSwitch"
        )

        XCTAssertEqual(AppStorageConfiguration.fallbackRuleFilename, "fallback-rule.json")
        XCTAssertEqual(
            url.path,
            applicationSupportDirectory
                .appending(path: "com.test.TypeSwitch", directoryHint: .isDirectory)
                .appending(path: AppStorageConfiguration.fallbackRuleFilename)
                .path
        )
        XCTAssertNotEqual(url, URL.appRulesStoreFileURL(
            applicationSupportDirectory: applicationSupportDirectory,
            bundleIdentifier: "com.test.TypeSwitch"
        ))
    }

    func testAppSwitchStatisticsStoreURLUsesStatisticsFilename() {
        let applicationSupportDirectory = URL(fileURLWithPath: "/tmp/Application Support", isDirectory: true)
        let url = URL.appSwitchStatisticsStoreFileURL(
            applicationSupportDirectory: applicationSupportDirectory,
            bundleIdentifier: "com.test.TypeSwitch"
        )

        XCTAssertEqual(AppStorageConfiguration.appSwitchStatisticsFilename, "app-switch-statistics.json")
        XCTAssertEqual(
            url.path,
            applicationSupportDirectory
                .appending(path: "com.test.TypeSwitch", directoryHint: .isDirectory)
                .appending(path: AppStorageConfiguration.appSwitchStatisticsFilename)
                .path
        )
        XCTAssertNotEqual(url, URL.appRulesStoreFileURL(
            applicationSupportDirectory: applicationSupportDirectory,
            bundleIdentifier: "com.test.TypeSwitch"
        ))
        XCTAssertNotEqual(url, URL.fallbackRuleStoreFileURL(
            applicationSupportDirectory: applicationSupportDirectory,
            bundleIdentifier: "com.test.TypeSwitch"
        ))
    }

    func testMergeRestoresMissingAndNoneRulesWithoutOverwritingExplicitStrategies() {
        let currentDate = Date(timeIntervalSince1970: 100)
        let legacyDate = Date(timeIntervalSince1970: 200)
        let currentRules = [
            "none": makeRule(bundleId: "none", strategy: .none, date: currentDate),
            "fixed": makeRule(bundleId: "fixed", strategy: .fixed(inputMethodId: "current.fixed"), date: currentDate),
            "followLast": makeRule(
                bundleId: "followLast",
                strategy: .followLast(lastInputMethodId: "current.last"),
                date: currentDate
            ),
            "ignored": makeRule(bundleId: "ignored", strategy: .ignored, date: currentDate),
        ]
        let legacyRules = [
            "missing": makeRule(bundleId: "missing", strategy: .fixed(inputMethodId: "legacy.missing"), date: legacyDate),
            "none": makeRule(bundleId: "none", strategy: .fixed(inputMethodId: "legacy.none"), date: legacyDate),
            "fixed": makeRule(bundleId: "fixed", strategy: .fixed(inputMethodId: "legacy.fixed"), date: legacyDate),
            "followLast": makeRule(bundleId: "followLast", strategy: .fixed(inputMethodId: "legacy.last"), date: legacyDate),
            "ignored": makeRule(bundleId: "ignored", strategy: .fixed(inputMethodId: "legacy.ignored"), date: legacyDate),
        ]

        let mergedRules = AppRulesStoreMigration.merge(
            currentRules: currentRules,
            legacyRules: legacyRules
        )

        XCTAssertEqual(mergedRules["missing"], legacyRules["missing"])
        XCTAssertEqual(mergedRules["none"], legacyRules["none"])
        XCTAssertEqual(mergedRules["fixed"], currentRules["fixed"])
        XCTAssertEqual(mergedRules["followLast"], currentRules["followLast"])
        XCTAssertEqual(mergedRules["ignored"], currentRules["ignored"])
    }

    func testMergeIsIdempotent() {
        let currentDate = Date(timeIntervalSince1970: 100)
        let legacyDate = Date(timeIntervalSince1970: 200)
        let currentRules = [
            "none": makeRule(bundleId: "none", strategy: .none, date: currentDate),
            "fixed": makeRule(bundleId: "fixed", strategy: .fixed(inputMethodId: "current.fixed"), date: currentDate),
        ]
        let legacyRules = [
            "none": makeRule(bundleId: "none", strategy: .fixed(inputMethodId: "legacy.none"), date: legacyDate),
            "fixed": makeRule(bundleId: "fixed", strategy: .fixed(inputMethodId: "legacy.fixed"), date: legacyDate),
        ]

        let firstMerge = AppRulesStoreMigration.merge(
            currentRules: currentRules,
            legacyRules: legacyRules
        )
        let secondMerge = AppRulesStoreMigration.merge(
            currentRules: firstMerge,
            legacyRules: legacyRules
        )

        XCTAssertEqual(secondMerge, firstMerge)
        XCTAssertEqual(secondMerge["fixed"]?.updatedAt, currentDate)
    }

    private func makeRule(
        bundleId: String,
        strategy: InputMethodStrategy,
        date: Date
    ) -> AppRuleRecord {
        AppRuleRecord(
            bundleId: bundleId,
            lastKnownPath: "/Applications/\(bundleId).app",
            lastKnownName: bundleId,
            strategy: strategy,
            createdAt: date,
            updatedAt: date
        )
    }
}
