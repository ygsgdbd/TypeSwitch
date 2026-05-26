import AppKit
import ComposableArchitecture
import SwiftUI
import SwiftUIX

/// 菜单栏主视图
struct MenuBarView: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        Group {
            RunningAppsView(store: store)
            ConfiguredAppsView(store: store)

            Divider()

            SettingsView(store: store)

            Divider()

            UnavailableAppsView(store: store)
            SwitchStatisticsView(store: store)

            Divider()

            AppInfoView()
        }
    }
}

#Preview {
    MenuBarView(
        store: Store(initialState: AppFeature.State()) {
            AppFeature()
        }
    )
}
