import ComposableArchitecture
import SwiftUI

/// 运行中的应用列表视图
struct RunningAppsView: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        Section(TypeSwitchStrings.Apps.Section.runningCount(store.runningMenuItems.count)) {
            ForEach(store.runningMenuItems) { item in
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
