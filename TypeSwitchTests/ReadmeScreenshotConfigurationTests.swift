import AppKit
import ComposableArchitecture
@testable import TypeSwitch
import XCTest

final class ReadmeScreenshotConfigurationTests: XCTestCase {
    func testArgumentsWithoutReadmeDemoDisableScreenshotMode() {
        XCTAssertNil(ReadmeScreenshotConfiguration(arguments: ["TypeSwitch"]))
    }

    func testArgumentsSelectRequestedAppearanceAndDisplay() throws {
        let configuration = try XCTUnwrap(
            ReadmeScreenshotConfiguration(
                arguments: [
                    "TypeSwitch",
                    "--readme-demo",
                    "--readme-appearance",
                    "dark",
                    "--readme-display-id",
                    "42",
                ]
            )
        )

        XCTAssertEqual(configuration.appearance, .dark)
        XCTAssertEqual(configuration.colorScheme, .dark)
        XCTAssertEqual(configuration.requestedDisplayID, 42)
    }

    func testMissingAppearanceDefaultsToLight() throws {
        let configuration = try XCTUnwrap(
            ReadmeScreenshotConfiguration(arguments: ["TypeSwitch", "--readme-demo"])
        )

        XCTAssertEqual(configuration.appearance, .light)
    }

    func testMissingOrInvalidScenarioDefaultsToFixed() throws {
        let argumentLists = [
            ["TypeSwitch", "--readme-demo"],
            ["TypeSwitch", "--readme-demo", "--readme-scenario"],
            ["TypeSwitch", "--readme-demo", "--readme-scenario", "invalid"],
        ]

        for arguments in argumentLists {
            let configuration = try XCTUnwrap(ReadmeScreenshotConfiguration(arguments: arguments))

            XCTAssertEqual(configuration.scenario, .fixed)
        }

        XCTAssertNil(ReadmeScreenshotConfiguration(arguments: ["TypeSwitch", "--readme-scenario", "default"]))
    }

    func testScenariosPreserveDistinctAppAndFallbackStrategies() throws {
        let abc = InputMethodStrategy.fixed(inputMethodId: "com.apple.keylayout.ABC")
        let pinyin = InputMethodStrategy.fixed(inputMethodId: "com.apple.inputmethod.SCIM.ITABC")
        let missing = InputMethodStrategy.fixed(inputMethodId: "com.example.missing-input-method")
        let cases: [(
            argument: String,
            appStrategy: InputMethodStrategy,
            fallbackStrategy: InputMethodStrategy,
            catalogStatus: SwitchingFeature.State.InputMethodCatalogStatus
        )] = [
            ("fixed", pinyin, abc, .loading),
            ("default", .none, abc, .ready),
            ("no-automatic-switch", .none, .none, .ready),
            ("follow-last", .followLast(lastInputMethodId: "com.apple.inputmethod.SCIM.ITABC"), abc, .ready),
            ("unrecorded", .followLast(lastInputMethodId: nil), abc, .ready),
            ("missing-fixed", missing, abc, .ready),
            ("missing-default", .none, missing, .ready),
            ("loading", missing, abc, .loading),
            ("unknown", missing, abc, .failed(.failedToFetchInputMethods)),
        ]

        for scenario in cases {
            let configuration = try XCTUnwrap(ReadmeScreenshotConfiguration(arguments: [
                "TypeSwitch", "--readme-demo", "--readme-scenario", scenario.argument,
            ]))
            let state = configuration.initialState(now: Date(timeIntervalSince1970: 1_800_000_000))

            XCTAssertEqual(configuration.scenario.rawValue, scenario.argument)
            XCTAssertTrue(state.isReadmeDemo)
            XCTAssertEqual(state.appRules["com.apple.Safari"]?.strategy, scenario.appStrategy, scenario.argument)
            XCTAssertEqual(state.fallbackStrategy, scenario.fallbackStrategy, scenario.argument)
            XCTAssertEqual(state.inputMethodCatalogStatus, scenario.catalogStatus, scenario.argument)
            XCTAssertEqual(state.inputMethods.map(\.name), ["ABC", "Pinyin"])
        }
    }

    func testHighestResolutionDisplayUsesPixelArea() {
        let displays = [
            ReadmeScreenshotConfiguration.Display(id: 1, pixelWidth: 2560, pixelHeight: 1440),
            ReadmeScreenshotConfiguration.Display(id: 2, pixelWidth: 3840, pixelHeight: 2160),
            ReadmeScreenshotConfiguration.Display(id: 3, pixelWidth: 3008, pixelHeight: 1692),
        ]

        XCTAssertEqual(
            ReadmeScreenshotConfiguration.highestResolutionDisplayID(in: displays),
            2
        )
    }

    @MainActor
    func testDarkAppearanceCanBeAppliedToNativeMenus() throws {
        let configuration = try XCTUnwrap(
            ReadmeScreenshotConfiguration(
                arguments: [
                    "TypeSwitch",
                    "--readme-demo",
                    "--readme-appearance",
                    "dark",
                ]
            )
        )
        let menu = NSMenu(title: "")

        configuration.applyAppearance(to: menu)

        XCTAssertEqual(menu.appearance?.name, .darkAqua)
    }

    func testDemoStateIsDeterministicAndCoversPrimaryMenuContent() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let configuration = try XCTUnwrap(
            ReadmeScreenshotConfiguration(arguments: ["TypeSwitch", "--readme-demo"])
        )

        let state = configuration.initialState(now: now)

        XCTAssertEqual(configuration.scenario, .fixed)
        XCTAssertTrue(state.isReadmeDemo)
        XCTAssertEqual(
            state.appRules["com.apple.Safari"]?.strategy,
            .fixed(inputMethodId: "com.apple.inputmethod.SCIM.ITABC")
        )
        XCTAssertEqual(state.fallbackStrategy, .fixed(inputMethodId: "com.apple.keylayout.ABC"))
        XCTAssertEqual(state.inputMethodCatalogStatus, .loading)
        XCTAssertEqual(state.currentFrontmostBundleId, "com.apple.Safari")
        XCTAssertEqual(state.inputMethods.map(\.name), ["ABC", "Pinyin"])
        XCTAssertEqual(state.runningApps.map(\.name), ["Safari", "Notes", "Terminal"])
        XCTAssertEqual(state.currentAppMenuItem?.name, "Safari")
        XCTAssertEqual(state.runningUnconfiguredMenuItems.map(\.name), ["Notes"])
        XCTAssertEqual(state.runningConfiguredMenuItems.map(\.name), ["Terminal"])
        XCTAssertEqual(state.configuredApps.map(\.name), ["Safari", "Terminal"])
        XCTAssertEqual(state.unavailableApps.map(\.name), ["Legacy Editor"])
        XCTAssertEqual(state.ignoredAppsForMenu.map(\.name), ["Messages"])
        XCTAssertEqual(state.fallbackSelectedLabel, "ABC")
        XCTAssertEqual(state.totalSuccessfulSwitchCount, 51)
        XCTAssertTrue(state.launchAtLoginEnabled)
        XCTAssertEqual(
            state.appRules["com.apple.Safari"]?.updatedAt,
            now
        )
    }

    @MainActor
    func testDemoStateIgnoresLiveTaskAndWriteActions() async throws {
        let configuration = try XCTUnwrap(
            ReadmeScreenshotConfiguration(arguments: ["TypeSwitch", "--readme-demo"])
        )
        let initialState = configuration.initialState(now: Date(timeIntervalSince1970: 1_800_000_000))
        let store = TestStore(initialState: initialState) {
            AppFeature()
        } withDependencies: {
            $0.appAvailabilityClient.pathExists = { _ in
                XCTFail("README demo mode must not inspect the file system")
                return false
            }
            $0.workspaceClient.frontmostApplication = {
                XCTFail("README demo mode must not inspect the live frontmost app")
                return nil
            }
            $0.workspaceClient.runningApplications = {
                XCTFail("README demo mode must not inspect live running apps")
                return []
            }
            $0.inputMethodClient.fetchInputMethods = {
                XCTFail("README demo mode must not inspect live input methods")
                return []
            }
            $0.launchAtLoginClient.status = {
                XCTFail("README demo mode must not inspect Login Items")
                return .disabled
            }
            $0.launchAtLoginClient.setEnabled = { _ in
                XCTFail("README demo mode must not modify Login Items")
                return .disabled
            }
        }

        await store.send(.task)
        await store.send(
            .view(.setStrategy(
                bundleId: "com.apple.Safari",
                strategy: .none
            ))
        )
        await store.send(.view(.setLaunchAtLogin(false)))

        XCTAssertEqual(store.state, initialState)

        await store.send(.menuPresented) {
            $0.isMenuPresented = true
            $0.menuStrategiesAtPresentation = initialState.appRules.mapValues(\.strategy)
        }
        XCTAssertEqual(store.state.configuredApps.map(\.name), ["Safari", "Terminal"])
    }
}
