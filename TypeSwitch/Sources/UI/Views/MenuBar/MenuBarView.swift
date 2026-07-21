import AppKit
import ComposableArchitecture
import Sparkle
import SwiftUI

/// 菜单栏主视图
struct MenuBarView: View {
    let store: StoreOf<AppFeature>
    let updateMonitor: SparkleUpdateMonitor
    let updaterController: SPUStandardUpdaterController

    var body: some View {
        Group {
            CurrentAppView(store: store)
            RunningAppsView(store: store)

            if store.currentAppMenuItem != nil
                || !store.runningUnconfiguredMenuItems.isEmpty
                || !store.runningConfiguredMenuItems.isEmpty
            {
                Divider()
            }

            ConfiguredAppsView(store: store)
            UnavailableAppsView(store: store)
            IgnoredAppsView(store: store)
            SwitchStatisticsView(store: store)

            Divider()

            SettingsView(store: store)

            Divider()

            AppInfoView(
                updateMonitor: updateMonitor,
                updaterController: updaterController
            )
        }
        .labelStyle(.titleAndIcon)
    }

    static func isRootMenuTrackingNotification(_ notification: Notification) -> Bool {
        guard let menu = notification.object as? NSMenu else {
            return false
        }
        return menu.supermenu == nil && menu !== NSApp.mainMenu
    }
}

private struct CurrentAppView: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        if let item = store.currentAppMenuItem {
            Section(TypeSwitchStrings.Apps.Section.currentApp) {
                AppRowView(
                    item: item,
                    inputMethods: store.inputMethods,
                    onIgnore: {
                        store.send(.view(.ignoreAppTapped(item.appInfo)))
                    }
                ) { strategy in
                    store.send(.view(.setStrategy(bundleId: item.bundleId, strategy: strategy)))
                }
            }
        }
    }
}

#Preview {
    MenuBarView(
        store: Store(initialState: AppFeature.State()) {
            AppFeature()
        },
        updateMonitor: SparkleUpdateMonitor(),
        updaterController: SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    )
}
