import Sparkle
@testable import TypeSwitch
import XCTest

@MainActor
final class SparkleUpdateMonitorTests: XCTestCase {
    func testStartSilentCheckBeginsProbingAndDisablesMenuAction() {
        let updater = UpdaterSpy()
        let monitor = SparkleUpdateMonitor()

        monitor.startSilentCheck(using: updater)

        XCTAssertEqual(updater.informationCheckCount, 1)
        XCTAssertEqual(monitor.status, .checking)
        XCTAssertFalse(monitor.isMenuActionEnabled)
        XCTAssertEqual(monitor.menuTitle, TypeSwitchStrings.Settings.General.checkForUpdates)
    }

    func testStartSilentCheckSkipsActiveUpdaterSession() {
        let updater = UpdaterSpy(sessionInProgress: true)
        let monitor = SparkleUpdateMonitor()

        monitor.startSilentCheck(using: updater)

        XCTAssertEqual(updater.informationCheckCount, 0)
        XCTAssertEqual(monitor.status, .idle)
        XCTAssertTrue(monitor.isMenuActionEnabled)
    }

    func testFoundUpdateChangesMenuAfterInformationCheckFinishes() {
        let updater = UpdaterSpy()
        let monitor = SparkleUpdateMonitor()
        monitor.startSilentCheck(using: updater)

        monitor.updater(delegateUpdater, didFindValidUpdate: .empty())

        XCTAssertEqual(monitor.status, .checking)

        monitor.updater(delegateUpdater, didFinishUpdateCycleFor: .updateInformation, error: nil)

        XCTAssertEqual(monitor.status, .updateAvailable)
        XCTAssertEqual(monitor.menuTitle, TypeSwitchStrings.Settings.General.updateAvailable)
        XCTAssertTrue(monitor.isMenuActionEnabled)
    }

    func testNoUpdateRestoresIdleState() {
        let updater = UpdaterSpy()
        let monitor = SparkleUpdateMonitor()
        monitor.startSilentCheck(using: updater)

        monitor.updater(delegateUpdater, didFinishUpdateCycleFor: .updateInformation, error: nil)

        XCTAssertEqual(monitor.status, .idle)
        XCTAssertEqual(monitor.menuTitle, TypeSwitchStrings.Settings.General.checkForUpdates)
        XCTAssertTrue(monitor.isMenuActionEnabled)
    }

    func testErrorDoesNotReportUpdateAfterFindingOne() {
        let updater = UpdaterSpy()
        let monitor = SparkleUpdateMonitor()
        monitor.startSilentCheck(using: updater)
        monitor.updater(delegateUpdater, didFindValidUpdate: .empty())

        monitor.updater(
            delegateUpdater,
            didFinishUpdateCycleFor: .updateInformation,
            error: NSError(domain: "SparkleUpdateMonitorTests", code: 1)
        )

        XCTAssertEqual(monitor.status, .idle)
        XCTAssertEqual(monitor.menuTitle, TypeSwitchStrings.Settings.General.checkForUpdates)
    }

    func testDelegateCallbacksOutsideSilentCheckAreIgnored() {
        let monitor = SparkleUpdateMonitor()

        monitor.updater(delegateUpdater, didFindValidUpdate: .empty())
        monitor.updater(delegateUpdater, didFinishUpdateCycleFor: .updateInformation, error: nil)

        XCTAssertEqual(monitor.status, .idle)
        XCTAssertEqual(monitor.menuTitle, TypeSwitchStrings.Settings.General.checkForUpdates)
    }

    func testUserCheckIsRejectedWhileCheckingAndAllowedAfterCompletion() {
        let updater = UpdaterSpy()
        let monitor = SparkleUpdateMonitor()
        monitor.startSilentCheck(using: updater)

        monitor.showUpdate(using: updater)

        XCTAssertEqual(updater.userCheckCount, 0)

        monitor.updater(delegateUpdater, didFinishUpdateCycleFor: .updateInformation, error: nil)
        monitor.showUpdate(using: updater)

        XCTAssertEqual(updater.userCheckCount, 1)
    }

    private var delegateUpdater: SPUUpdater {
        SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        ).updater
    }
}

@MainActor
private final class UpdaterSpy: SparkleUpdateChecking {
    var sessionInProgress: Bool
    private(set) var informationCheckCount = 0
    private(set) var userCheckCount = 0

    init(sessionInProgress: Bool = false) {
        self.sessionInProgress = sessionInProgress
    }

    func checkForUpdateInformation() {
        informationCheckCount += 1
    }

    func checkForUpdates() {
        userCheckCount += 1
    }
}
