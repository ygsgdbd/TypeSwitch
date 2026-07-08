import AppKit
import ComposableArchitecture
import Sparkle
import SwiftUI

@main
struct TypeSwitchApp: App {
    let store: StoreOf<AppFeature>
    let updaterController: SPUStandardUpdaterController

    init() {
        self.store = Store(initialState: AppFeature.State()) {
            AppFeature()
        }
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.store.send(.task)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(store: store, updaterController: updaterController)
        } label: {
            MenuBarIconView(store: store)
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MenuBarIconView: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        Image(systemName: store.menuBarIconSystemName)
    }
}
