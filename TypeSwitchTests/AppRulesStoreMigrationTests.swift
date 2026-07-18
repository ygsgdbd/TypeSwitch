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

    func testPrepareStoreCreatesBundleDirectoryWhenStoreMissing() throws {
        let fileManager = FileManager.default
        let rootDirectory = fileManager.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true, attributes: nil)
        defer { try? fileManager.removeItem(at: rootDirectory) }

        let currentStoreURL = URL.appRulesStoreFileURL(applicationSupportDirectory: rootDirectory)

        let result = try AppRulesStoreMigration.prepareStore(
            currentStoreURL: currentStoreURL,
            fileManager: fileManager
        )

        XCTAssertEqual(result, .noStoreFound)
        XCTAssertFalse(fileManager.fileExists(atPath: currentStoreURL.path))
        XCTAssertTrue(fileManager.fileExists(atPath: currentStoreURL.deletingLastPathComponent().path))
    }

    func testPrepareStoreReportsCurrentStorePresentWhenFileExists() throws {
        let fileManager = FileManager.default
        let rootDirectory = fileManager.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true, attributes: nil)
        defer { try? fileManager.removeItem(at: rootDirectory) }

        let currentStoreURL = URL.appRulesStoreFileURL(applicationSupportDirectory: rootDirectory)
        let currentStore = AppRulesStore(
            rules: [
                "current": AppRuleRecord(
                    bundleId: "current",
                    lastKnownPath: "/Applications/Current.app",
                    lastKnownName: "Current",
                    strategy: .none,
                    createdAt: Date(timeIntervalSince1970: 50),
                    updatedAt: Date(timeIntervalSince1970: 60)
                ),
            ]
        )
        try fileManager.createDirectory(
            at: currentStoreURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        let currentData = try JSONEncoder().encode(currentStore)
        try currentData.write(to: currentStoreURL, options: [.atomic])

        let result = try AppRulesStoreMigration.prepareStore(
            currentStoreURL: currentStoreURL,
            fileManager: fileManager
        )

        XCTAssertEqual(result, .currentStorePresent)
        XCTAssertEqual(try Data(contentsOf: currentStoreURL), currentData)
    }
}
