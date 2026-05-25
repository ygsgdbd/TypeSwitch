import ComposableArchitecture
import SwiftUI

struct UnavailableAppsView: View {
    let store: StoreOf<AppFeature>
    
    var body: some View {
        if !store.unavailableApps.isEmpty {
            Section {
                Menu(TypeSwitchStrings.Apps.Section.unavailableCount(store.unavailableApps.count)) {
                    Button(TypeSwitchStrings.Apps.clearUnavailable) {
                        store.send(.removeUnavailableRulesTapped)
                    }
                    
                    Divider()
                    
                    ForEach(store.unavailableApps) { item in
                        AppRowView(
                            item: item,
                            inputMethods: store.inputMethods
                        ) { strategy in
                            store.send(.setStrategy(bundleId: item.bundleId, strategy: strategy))
                        }
                    }
                }
            }
        }
    }
}
