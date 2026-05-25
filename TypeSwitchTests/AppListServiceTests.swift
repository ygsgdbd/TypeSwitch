import AppKit
import Foundation
import XCTest
@testable import TypeSwitch

final class AppListServiceTests: XCTestCase {
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
}
