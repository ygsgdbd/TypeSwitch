import SwiftUI

/// 设置视图，包含各种应用设置选项
struct SettingsView: View {
    @State private var isLaunchAtLoginEnabled = LaunchAtLoginService.isEnabled
    
    var body: some View {
        Section {
            Toggle(TypeSwitchStrings.Settings.General.autoLaunch, isOn: $isLaunchAtLoginEnabled)
                .toggleStyle(.checkbox)
                .onChange(of: isLaunchAtLoginEnabled) { newValue in
                    _ = LaunchAtLoginService.setLaunchAtLogin(newValue)
                }
        }
    }
}
