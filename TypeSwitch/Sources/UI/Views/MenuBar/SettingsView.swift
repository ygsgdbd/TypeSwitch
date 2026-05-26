import ComposableArchitecture
import SwiftUI

/// 设置视图，包含各种应用设置选项
struct SettingsView: View {
    @Bindable var store: StoreOf<AppFeature>

    var body: some View {
        Section {
            Menu {
                InputMethodStrategyMenuContent(
                    context: .fallbackRule,
                    strategy: store.fallbackStrategy,
                    inputMethods: store.inputMethods,
                    defaultOptionLabel: TypeSwitchStrings.InputMethod.fallbackDefaultOption,
                    followLastOptionLabel: TypeSwitchStrings.InputMethod.followLastEmptyOption
                ) { strategy in
                    store.send(.view(.setFallbackStrategy(strategy)))
                }
            } label: {
                Text(TypeSwitchStrings.Settings.Fallback.defaultInputMethod)
                if let selectedLabel = store.fallbackSelectedLabel {
                    Text(selectedLabel)
                        .foregroundStyle(store.fallbackHasMissingInputMethod ? .secondary : .primary)
                }
            }

            Toggle(
                TypeSwitchStrings.Settings.General.autoLaunch,
                isOn: Binding(
                    get: { store.launchAtLoginEnabled },
                    set: { store.send(.view(.setLaunchAtLogin($0))) }
                )
            )
            .toggleStyle(.checkbox)

            if store.launchAtLoginRequiresApproval {
                Text(TypeSwitchStrings.Settings.General.autoLaunchRequiresApproval)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button(TypeSwitchStrings.Settings.General.openLoginItems) {
                    LaunchAtLoginService.openSystemSettingsLoginItems()
                }
            }
        }
    }
}
