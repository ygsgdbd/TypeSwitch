import AppKit
import Foundation
@testable import TypeSwitch
import XCTest

final class AppListServiceTests: XCTestCase {
    func testAppInfoBundleURLUsesLocalizedBundleDisplayName() throws {
        let appURL = try makeAppBundle(
            identifier: "com.test.localized",
            displayName: "Raw Test App",
            localizedDisplayName: "本地化测试"
        )

        let appInfo = AppInfo(bundleURL: appURL)

        XCTAssertEqual(appInfo?.bundleId, "com.test.localized")
        XCTAssertEqual(appInfo?.name, "本地化测试")
        XCTAssertEqual(appInfo?.path, appURL.path)
    }

    func testAppInfoBundleURLFallsBackToRawBundleDisplayName() throws {
        let appURL = try makeAppBundle(
            identifier: "com.test.fallback",
            displayName: "Raw Test App"
        )

        let appInfo = AppInfo(bundleURL: appURL)

        XCTAssertEqual(appInfo?.bundleId, "com.test.fallback")
        XCTAssertEqual(appInfo?.name, "Raw Test App")
        XCTAssertEqual(appInfo?.path, appURL.path)
    }

    func testShouldTrackRunningApplicationIncludesRegularAppBundle() {
        XCTAssertTrue(
            AppListService.shouldTrackRunningApplication(
                activationPolicy: .regular,
                bundleIdentifier: "com.test.browser",
                bundleURL: URL(fileURLWithPath: "/Applications/Browser.app")
            )
        )
    }

    func testShouldTrackRunningApplicationExcludesAccessoryAndBackgroundApps() {
        XCTAssertFalse(
            AppListService.shouldTrackRunningApplication(
                activationPolicy: .accessory,
                bundleIdentifier: "com.test.widget",
                bundleURL: URL(fileURLWithPath: "/Applications/Widget.app")
            )
        )

        XCTAssertFalse(
            AppListService.shouldTrackRunningApplication(
                activationPolicy: .prohibited,
                bundleIdentifier: "com.test.agent",
                bundleURL: URL(fileURLWithPath: "/Applications/Agent.app")
            )
        )
    }

    func testShouldTrackRunningApplicationExcludesNonAppBundlesAndMissingMetadata() {
        XCTAssertFalse(
            AppListService.shouldTrackRunningApplication(
                activationPolicy: .regular,
                bundleIdentifier: "com.test.extension",
                bundleURL: URL(fileURLWithPath: "/Applications/Widget.appex")
            )
        )

        XCTAssertFalse(
            AppListService.shouldTrackRunningApplication(
                activationPolicy: .regular,
                bundleIdentifier: nil,
                bundleURL: URL(fileURLWithPath: "/Applications/Browser.app")
            )
        )

        XCTAssertFalse(
            AppListService.shouldTrackRunningApplication(
                activationPolicy: .regular,
                bundleIdentifier: "com.test.cli",
                bundleURL: nil
            )
        )
    }

    private func makeAppBundle(
        identifier: String,
        displayName: String,
        localizedDisplayName: String? = nil
    ) throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TypeSwitchTests-\(UUID().uuidString)", isDirectory: true)
        let appURL = rootURL.appendingPathComponent("Test.app", isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)

        try FileManager.default.createDirectory(
            at: resourcesURL,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let infoPlist: [String: Any] = [
            "CFBundleDevelopmentRegion": "zh-Hans",
            "CFBundleDisplayName": displayName,
            "CFBundleIdentifier": identifier,
            "CFBundleName": displayName,
            "CFBundlePackageType": "APPL",
        ]
        let infoPlistData = try PropertyListSerialization.data(
            fromPropertyList: infoPlist,
            format: .xml,
            options: 0
        )
        try infoPlistData.write(to: contentsURL.appendingPathComponent("Info.plist"))

        if let localizedDisplayName {
            let localizedResourcesURL = resourcesURL.appendingPathComponent(
                "zh-Hans.lproj",
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: localizedResourcesURL,
                withIntermediateDirectories: true
            )
            try """
            "CFBundleDisplayName" = "\(localizedDisplayName)";
            "CFBundleName" = "\(localizedDisplayName)";
            """.write(
                to: localizedResourcesURL.appendingPathComponent("InfoPlist.strings"),
                atomically: true,
                encoding: .utf8
            )
        }

        return appURL
    }
}
