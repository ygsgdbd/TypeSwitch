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
            ConfiguredAppsView(store: store)
            UnavailableAppsView(store: store)
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
}

private struct CurrentAppView: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        if let item = store.currentAppMenuItem {
            Section(TypeSwitchStrings.Apps.Section.currentApp) {
                AppRowView(
                    item: item,
                    inputMethods: store.inputMethods
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
