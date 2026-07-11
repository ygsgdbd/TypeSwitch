import ComposableArchitecture
import SwiftUI

/// 已配置的应用列表视图
struct ConfiguredAppsView: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        if !store.configuredApps.isEmpty {
            Section {
                Menu {
                    if store.hasMissingInputMethodRules {
                        Button(role: .destructive) {
                            if MenuConfirmation.confirm(
                                title: TypeSwitchStrings.InputMethod.ClearMissingConfirmation.title,
                                message: TypeSwitchStrings.InputMethod.ClearMissingConfirmation.message,
                                confirmButton: TypeSwitchStrings.InputMethod.ClearMissingConfirmation.confirm
                            ) {
                                store.send(.view(.removeMissingInputMethodRulesTapped))
                            }
                        } label: {
                            Label(
                                TypeSwitchStrings.InputMethod.clearMissingConfiguration,
                                systemImage: "trash"
                            )
                        }

                        Divider()
                    }

                    ForEach(store.configuredApps) { item in
                        AppRowView(
                            item: item,
                            inputMethods: store.inputMethods
                        ) { strategy in
                            store.send(.view(.setStrategy(bundleId: item.bundleId, strategy: strategy)))
                        }
                    }
                } label: {
                    Label(
                        TypeSwitchStrings.Apps.Section.configuredCount(store.configuredApps.count),
                        systemImage: "list.bullet.rectangle"
                    )
                }
            }
        }
    }
}
