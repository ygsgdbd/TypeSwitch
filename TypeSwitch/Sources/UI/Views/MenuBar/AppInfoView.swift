import AppKit
import SwiftUI

/// 应用信息视图，显示版本信息和相关链接
struct AppInfoView: View {
    var body: some View {
        Section {
            // 版本信息
            Text(TypeSwitchStrings.App.about(AppInfoService.fullVersionInfo))
                .foregroundColor(.secondary)
            
            Divider()
            
            // 相关链接
            Button(TypeSwitchStrings.App.githubRepository) {
                AppInfoService.openGitHubRepository()
            }
            
            Button(TypeSwitchStrings.App.latestRelease) {
                AppInfoService.openLatestRelease()
            }
            
            Divider()
            
            // 退出应用
            Button(TypeSwitchStrings.Menu.quit, role: .destructive) {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}
