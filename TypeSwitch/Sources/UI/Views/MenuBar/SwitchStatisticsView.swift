import ComposableArchitecture
import SwiftUI

struct SwitchStatisticsView: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        Section {
            Menu(TypeSwitchStrings.SwitchStatistics.menuTitle(store.totalSuccessfulSwitchCount)) {
                if store.switchStatisticsItems.isEmpty {
                    Text(TypeSwitchStrings.SwitchStatistics.empty)
                        .foregroundStyle(.secondary)
                } else {
                    Text(TypeSwitchStrings.SwitchStatistics.totalCount(store.totalSuccessfulSwitchCount))

                    Divider()

                    ForEach(store.switchStatisticsItems) { item in
                        Button {} label: {
                            if item.path != nil {
                                AppInfo(bundleId: item.bundleId, name: item.name, path: item.path).icon
                            }
                            Text(item.name)
                            Text(TypeSwitchStrings.SwitchStatistics.appCount(item.count))
                        }
                        .disabled(true)
                    }

                    Divider()

                    Button(TypeSwitchStrings.SwitchStatistics.clear, role: .destructive) {
                        if MenuConfirmation.confirm(
                            title: TypeSwitchStrings.SwitchStatistics.ClearConfirmation.title,
                            message: TypeSwitchStrings.SwitchStatistics.ClearConfirmation.message,
                            confirmButton: TypeSwitchStrings.SwitchStatistics.ClearConfirmation.confirm
                        ) {
                            store.send(.view(.clearSwitchStatisticsTapped))
                        }
                    }
                }
            }
        }
    }
}
