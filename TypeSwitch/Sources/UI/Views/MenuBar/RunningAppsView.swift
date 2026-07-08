import ComposableArchitecture
import SwiftUI

/// 运行中的应用列表视图
struct RunningAppsView: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        Group {
            if !store.runningUnconfiguredMenuItems.isEmpty {
                Section(TypeSwitchStrings.Apps.Section.unconfiguredCount(store.runningUnconfiguredMenuItems.count)) {
                    ForEach(store.runningUnconfiguredMenuItems) { item in
                        AppRowView(
                            item: item,
                            inputMethods: store.inputMethods
                        ) { strategy in
                            store.send(.view(.setStrategy(bundleId: item.bundleId, strategy: strategy)))
                        }
                    }
                }
            }

            if !store.runningConfiguredMenuItems.isEmpty {
                Section(TypeSwitchStrings.Apps.Section.runningCount(store.runningConfiguredMenuItems.count)) {
                    ForEach(store.runningConfiguredMenuItems) { item in
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
    }
}
