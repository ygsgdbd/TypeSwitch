import ComposableArchitecture
import SwiftUI

struct UnavailableAppsView: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        if !store.unavailableApps.isEmpty {
            Section {
                Menu {
                    Button(role: .destructive) {
                        if MenuConfirmation.confirm(
                            title: TypeSwitchStrings.Apps.ClearUnavailableConfirmation.title,
                            message: TypeSwitchStrings.Apps.ClearUnavailableConfirmation.message,
                            confirmButton: TypeSwitchStrings.Apps.ClearUnavailableConfirmation.confirm
                        ) {
                            store.send(.view(.removeUnavailableRulesTapped))
                        }
                    } label: {
                        Label(TypeSwitchStrings.Apps.clearUnavailable, systemImage: "trash")
                    }

                    Divider()

                    ForEach(store.unavailableApps) { item in
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
                } label: {
                    Label(
                        TypeSwitchStrings.Apps.Section.unavailableCount(store.unavailableApps.count),
                        systemImage: "exclamationmark.triangle"
                    )
                }
            }
        }
    }
}
