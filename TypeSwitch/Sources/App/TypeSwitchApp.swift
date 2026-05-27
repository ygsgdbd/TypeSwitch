import AppKit
import ComposableArchitecture
import SwiftUIX

@main
struct TypeSwitchApp: App {
    let store: StoreOf<AppFeature>

    init() {
        self.store = Store(initialState: AppFeature.State()) {
            AppFeature()
        }
        self.store.send(.task)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(store: store)
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
