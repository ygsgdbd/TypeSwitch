import ComposableArchitecture
import Sparkle
import SwiftUI

/// 设置视图，包含各种应用设置选项
struct SettingsView: View {
    @Bindable var store: StoreOf<AppFeature>
    let updaterController: SPUStandardUpdaterController

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
                Label(
                    TypeSwitchStrings.Settings.Fallback.defaultInputMethod,
                    systemImage: "keyboard"
                )
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

                Button {
                    LaunchAtLoginService.openSystemSettingsLoginItems()
                } label: {
                    Label(TypeSwitchStrings.Settings.General.openLoginItems, systemImage: "gear")
                }
            }

            Button {
                updaterController.checkForUpdates(nil)
            } label: {
                Label(
                    TypeSwitchStrings.Settings.General.checkForUpdates,
                    systemImage: "arrow.triangle.2.circlepath"
                )
            }
        }
    }
}
