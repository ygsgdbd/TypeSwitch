import Sparkle
import SwiftUI

@MainActor
protocol SparkleUpdateChecking: AnyObject {
    var sessionInProgress: Bool { get }

    func checkForUpdateInformation()
    func checkForUpdates()
}

extension SPUUpdater: SparkleUpdateChecking {}

@MainActor
final class SparkleUpdateMonitor: NSObject, ObservableObject {
    enum Status: Equatable {
        case idle
        case checking
        case updateAvailable
    }

    @Published private(set) var status: Status = .idle

    var menuTitle: String {
        status == .updateAvailable
            ? TypeSwitchStrings.Settings.General.updateAvailable
            : TypeSwitchStrings.Settings.General.checkForUpdates
    }

    var isMenuActionEnabled: Bool {
        status != .checking
    }

    private var foundUpdate = false

    func startSilentCheck(using updater: SparkleUpdateChecking) {
        guard status != .checking, !updater.sessionInProgress else { return }

        foundUpdate = false
        status = .checking
        updater.checkForUpdateInformation()
    }

    func showUpdate(using updater: SparkleUpdateChecking) {
        guard status != .checking else { return }

        updater.checkForUpdates()
    }

    private func recordFoundUpdate() {
        guard status == .checking else { return }
        foundUpdate = true
    }

    private func finishSilentCheck(error: Error?) {
        guard status == .checking else { return }
        status = error == nil && foundUpdate ? .updateAvailable : .idle
        foundUpdate = false
    }
}

extension SparkleUpdateMonitor: SPUUpdaterDelegate {
    func updater(_: SPUUpdater, didFindValidUpdate _: SUAppcastItem) {
        recordFoundUpdate()
    }

    func updater(
        _: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        guard updateCheck == .updateInformation else { return }
        finishSilentCheck(error: error)
    }
}
