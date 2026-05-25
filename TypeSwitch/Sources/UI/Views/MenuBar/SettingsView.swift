import ComposableArchitecture
import SwiftUI

/// 设置视图，包含各种应用设置选项
struct SettingsView: View {
    @Bindable var store: StoreOf<AppFeature>
    
    var body: some View {
        Section {
            Menu {
                InputMethodStrategyMenuContent(
                    strategy: store.fallbackStrategy,
                    inputMethods: store.inputMethods,
                    followLastOptionLabel: store.fallbackFollowLastOptionLabel
                ) { strategy in
                    store.send(.setFallbackStrategy(strategy))
                }
            } label: {
                Text(String(localized: "settings.fallback.default_input_method"))
                if let selectedLabel = store.fallbackSelectedLabel {
                    Text(selectedLabel)
                        .foregroundStyle(store.fallbackHasMissingInputMethod ? .secondary : .primary)
                }
            }
            
            Text(String(localized: "settings.fallback.default_input_method_description"))
                .font(.footnote)
                .foregroundStyle(.secondary)

            Toggle(
                TypeSwitchStrings.Settings.General.autoLaunch,
                isOn: Binding(
                    get: { store.launchAtLoginEnabled },
                    set: { store.send(.setLaunchAtLogin($0)) }
                )
            )
            .toggleStyle(.checkbox)

            if store.launchAtLoginRequiresApproval {
                Text(String(localized: "settings.general.auto_launch_requires_approval"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button(String(localized: "settings.general.open_login_items")) {
                    LaunchAtLoginService.openSystemSettingsLoginItems()
                }
            }
        }
    }
}
