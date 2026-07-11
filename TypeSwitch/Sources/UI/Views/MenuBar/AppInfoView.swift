import AppKit
import SwiftUI

/// 应用信息视图，显示项目链接和退出入口
struct AppInfoView: View {
    var body: some View {
        Section {
            // GitHub 仓库
            Button {
                AppInfoService.openGitHubRepository()
            } label: {
                Label("GitHub", systemImage: "link")
            }

            Divider()

            // 退出应用
            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label(TypeSwitchStrings.Menu.quit, systemImage: "power")
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}
