import AppKit
import SwiftUI

/// 应用信息视图，显示项目链接和退出入口
struct AppInfoView: View {
    var body: some View {
        Section {
            // GitHub 仓库
            Button(TypeSwitchStrings.App.github) {
                AppInfoService.openGitHubRepository()
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
