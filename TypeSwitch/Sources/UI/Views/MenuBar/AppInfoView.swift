import AppKit
import SwiftUI

/// 应用信息视图，显示关于面板和退出入口
struct AppInfoView: View {
    var body: some View {
        Section {
            // 关于面板
            Button(TypeSwitchStrings.App.about) {
                AppInfoService.openAboutWindow()
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
