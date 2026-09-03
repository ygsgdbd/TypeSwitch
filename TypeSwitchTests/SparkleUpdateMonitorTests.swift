import Combine
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
        XCTAssertEqual(
            monitor.menuTitle,
            TypeSwitchStrings.Settings.General.checkingForUpdates
        )
    }

    func testStartSilentCheckSkipsActiveUpdaterSession() {
        let updater = UpdaterSpy(sessionInProgress: true)
        let monitor = SparkleUpdateMonitor()

        monitor.startSilentCheck(using: updater)

        XCTAssertEqual(updater.informationCheckCount, 0)
        XCTAssertEqual(monitor.status, .idle)
        XCTAssertTrue(monitor.isMenuActionEnabled)
    }

    func testFoundUpdateShowsDisplayVersionAfterInformationCheckFinishes() {
        let updater = UpdaterSpy()
        let monitor = SparkleUpdateMonitor()
        let update = SUAppcastItem.empty()
        monitor.startSilentCheck(using: updater)

        monitor.updater(delegateUpdater, didFindValidUpdate: update)

        XCTAssertEqual(monitor.status, .checking)

        monitor.updater(delegateUpdater, didFinishUpdateCycleFor: .updateInformation, error: nil)

        XCTAssertEqual(
            monitor.status,
            .updateAvailable(version: update.displayVersionString)
        )
        XCTAssertEqual(
            monitor.menuTitle,
            TypeSwitchStrings.Settings.General.updateAvailable(update.displayVersionString)
        )
        XCTAssertTrue(monitor.isMenuActionEnabled)
    }

    func testSuccessfulCheckWithoutUpdateRestoresIdleState() {
        let updater = UpdaterSpy()
        let monitor = SparkleUpdateMonitor()
        monitor.startSilentCheck(using: updater)

        monitor.updater(
            delegateUpdater,
            didFinishUpdateCycleFor: .updateInformation,
            error: noUpdateError
        )

        XCTAssertEqual(monitor.status, .idle)
        XCTAssertEqual(
            monitor.menuTitle,
            TypeSwitchStrings.Settings.General.checkForUpdates
        )
    }

    func testFinishingCheckWhileMenuIsTrackedDefersVisibleStateUntilTrackingEnds() {
        let updater = UpdaterSpy()
        let monitor = SparkleUpdateMonitor()
        monitor.startSilentCheck(using: updater)
        monitor.menuTrackingDidBegin()

        monitor.updater(
            delegateUpdater,
            didFinishUpdateCycleFor: .updateInformation,
            error: noUpdateError
        )

        XCTAssertEqual(monitor.status, .checking)
        XCTAssertEqual(
            monitor.menuTitle,
            TypeSwitchStrings.Settings.General.checkingForUpdates
        )
        XCTAssertFalse(monitor.isMenuActionEnabled)

        monitor.menuTrackingDidEnd()

        XCTAssertEqual(monitor.status, .idle)
        XCTAssertEqual(
            monitor.menuTitle,
            TypeSwitchStrings.Settings.General.checkForUpdates
        )
        XCTAssertTrue(monitor.isMenuActionEnabled)
    }

    func testMenuTrackingPublishesOnlyFinalStatusWhenTrackingEnds() {
        let updater = UpdaterSpy()
        let monitor = SparkleUpdateMonitor()
        let update = SUAppcastItem.empty()
        monitor.startSilentCheck(using: updater)
        var publishedStatuses: [SparkleUpdateMonitor.Status] = []
        let cancellable = monitor.$status.dropFirst().sink {
            publishedStatuses.append($0)
        }
        monitor.menuTrackingDidBegin()

        monitor.updater(delegateUpdater, didFindValidUpdate: update)
        monitor.updater(delegateUpdater, didFinishUpdateCycleFor: .updateInformation, error: nil)

        XCTAssertTrue(publishedStatuses.isEmpty)

        monitor.menuTrackingDidEnd()

        XCTAssertEqual(
            publishedStatuses,
            [.updateAvailable(version: update.displayVersionString)]
        )
        withExtendedLifetime(cancellable) {}
    }

    func testNoUpdateClearsPreviouslyKnownUpdate() {
        let updater = UpdaterSpy()
        let monitor = SparkleUpdateMonitor()
        monitor.updater(delegateUpdater, didFindValidUpdate: .empty())
        monitor.startSilentCheck(using: updater)

        monitor.updater(
            delegateUpdater,
            didFinishUpdateCycleFor: .updateInformation,
            error: noUpdateError
        )

        XCTAssertEqual(monitor.status, .idle)
    }

    func testFailedCheckPreservesPreviouslyKnownUpdate() {
        let updater = UpdaterSpy()
        let monitor = SparkleUpdateMonitor()
        let update = SUAppcastItem.empty()
        monitor.updater(delegateUpdater, didFindValidUpdate: update)
        monitor.startSilentCheck(using: updater)

        monitor.updater(
            delegateUpdater,
            didFinishUpdateCycleFor: .updateInformation,
            error: NSError(domain: "SparkleUpdateMonitorTests", code: 1)
        )

        XCTAssertEqual(
            monitor.status,
            .updateAvailable(version: update.displayVersionString)
        )
    }

    func testFailedCheckWhileMenuIsTrackedRestoresKnownUpdateAfterTrackingEnds() {
        let updater = UpdaterSpy()
        let monitor = SparkleUpdateMonitor()
        let update = SUAppcastItem.empty()
        monitor.handleScheduledUpdate(update)
        monitor.startSilentCheck(using: updater)
        monitor.menuTrackingDidBegin()

        monitor.updater(
            delegateUpdater,
            didFinishUpdateCycleFor: .updateInformation,
            error: NSError(domain: "SparkleUpdateMonitorTests", code: 1)
        )

        XCTAssertEqual(monitor.status, .checking)

        monitor.menuTrackingDidEnd()

        XCTAssertEqual(
            monitor.status,
            .updateAvailable(version: update.displayVersionString)
        )
    }

    func testFailedCheckDoesNotPublishPendingUpdate() {
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
    }

    func testScheduledUpdateUsesGentleReminderAndUpdatesMenuState() {
        let monitor = SparkleUpdateMonitor()
        let update = SUAppcastItem.empty()

        XCTAssertNoThrow(
            try monitor.updater(delegateUpdater, mayPerform: .updatesInBackground)
        )
        XCTAssertEqual(monitor.status, .checking)
        XCTAssertFalse(monitor.isMenuActionEnabled)

        monitor.updater(delegateUpdater, didFindValidUpdate: update)

        let standardDriverHandlesUpdate = monitor.standardUserDriverShouldHandleShowingScheduledUpdate(
            update,
            andInImmediateFocus: true
        )

        XCTAssertTrue(monitor.supportsGentleScheduledUpdateReminders)
        XCTAssertFalse(standardDriverHandlesUpdate)
        monitor.handleScheduledUpdate(update)

        XCTAssertEqual(
            monitor.status,
            .updateAvailable(version: update.displayVersionString)
        )
        XCTAssertTrue(monitor.isMenuActionEnabled)
    }

    func testScheduledNoUpdateRestoresIdleState() {
        let monitor = SparkleUpdateMonitor()

        XCTAssertNoThrow(
            try monitor.updater(delegateUpdater, mayPerform: .updatesInBackground)
        )
        monitor.updater(
            delegateUpdater,
            didFinishUpdateCycleFor: .updatesInBackground,
            error: noUpdateError
        )

        XCTAssertEqual(monitor.status, .idle)
        XCTAssertTrue(monitor.isMenuActionEnabled)
    }

    func testScheduledUpdateWhileMenuIsTrackedDefersVisibleStateUntilTrackingEnds() {
        let updater = UpdaterSpy()
        let monitor = SparkleUpdateMonitor()
        let update = SUAppcastItem.empty()
        monitor.menuTrackingDidBegin()

        XCTAssertNoThrow(
            try monitor.updater(delegateUpdater, mayPerform: .updatesInBackground)
        )
        monitor.showUpdate(using: updater)
        monitor.updater(delegateUpdater, didFindValidUpdate: update)
        monitor.handleScheduledUpdate(update)
        monitor.updater(delegateUpdater, didFinishUpdateCycleFor: .updatesInBackground, error: nil)

        XCTAssertEqual(monitor.status, .idle)
        XCTAssertEqual(
            monitor.menuTitle,
            TypeSwitchStrings.Settings.General.checkForUpdates
        )
        XCTAssertTrue(monitor.isMenuActionEnabled)
        XCTAssertEqual(updater.userCheckCount, 0)

        monitor.menuTrackingDidEnd()

        XCTAssertEqual(
            monitor.status,
            .updateAvailable(version: update.displayVersionString)
        )
        XCTAssertEqual(
            monitor.menuTitle,
            TypeSwitchStrings.Settings.General.updateAvailable(update.displayVersionString)
        )
        XCTAssertTrue(monitor.isMenuActionEnabled)
    }

    func testUserCheckUsesCanCheckForUpdatesEvenWhenSessionIsActive() {
        let updater = UpdaterSpy()
        let monitor = SparkleUpdateMonitor()
        monitor.startSilentCheck(using: updater)

        monitor.showUpdate(using: updater)

        XCTAssertEqual(updater.userCheckCount, 0)

        monitor.updater(delegateUpdater, didFinishUpdateCycleFor: .updateInformation, error: nil)
        updater.sessionInProgress = true
        monitor.showUpdate(using: updater)

        XCTAssertEqual(updater.userCheckCount, 1)

        updater.canCheckForUpdates = false
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

    private var noUpdateError: NSError {
        NSError(
            domain: SUSparkleErrorDomain,
            code: Int(SUError.noUpdateError.rawValue)
        )
    }
}

@MainActor
private final class UpdaterSpy: SparkleUpdateChecking {
    var canCheckForUpdates: Bool
    var sessionInProgress: Bool
    private(set) var informationCheckCount = 0
    private(set) var userCheckCount = 0

    init(canCheckForUpdates: Bool = true, sessionInProgress: Bool = false) {
        self.canCheckForUpdates = canCheckForUpdates
        self.sessionInProgress = sessionInProgress
    }

    func checkForUpdateInformation() {
        informationCheckCount += 1
    }

    func checkForUpdates() {
        userCheckCount += 1
    }
}
