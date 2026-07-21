import ComposableArchitecture
import SwiftUI

struct IgnoredAppsView: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        if !store.ignoredAppsForMenu.isEmpty {
            Menu {
                Section {
                    ForEach(store.ignoredAppsForMenu) { app in
                        Button {
                            store.send(.view(.restoreIgnoredAppTapped(bundleId: app.bundleId)))
                        } label: {
                            Label {
                                Text(app.name)
                            } icon: {
                                app.icon
                            }
                        }
                    }
                } header: {
                    Text(TypeSwitchStrings.Apps.Ignored.restoreHint)
                }

                Divider()

                Button {
                    store.send(.view(.restoreAllIgnoredAppsTapped))
                } label: {
                    Label(
                        TypeSwitchStrings.Apps.Ignored.restoreAll,
                        systemImage: "arrow.uturn.backward"
                    )
                }
            } label: {
                Label(
                    TypeSwitchStrings.Apps.Ignored.menuTitle(store.ignoredAppsForMenu.count),
                    systemImage: "eye.slash"
                )
            }
        }
    }
}
