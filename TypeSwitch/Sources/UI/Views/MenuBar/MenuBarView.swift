import AppKit
import SwiftUI
import SwiftUIX

/// 菜单栏主视图
struct MenuBarView: View {
    @EnvironmentObject private var viewModel: InputMethodManager
    
    var body: some View {
        Group {
            RunningAppsView()
            ConfiguredAppsView()
            
            Divider()
            
            SettingsView()
            
            Divider()
            
            AppInfoView()
        }
    }
}

#Preview {
    MenuBarView()
        .environmentObject(InputMethodManager.shared)
}
