import AppKit
import Sparkle
import SwiftUI

/// 应用信息视图，显示项目链接和退出入口
struct AppInfoView: View {
    @ObservedObject var updateMonitor: SparkleUpdateMonitor
    let updaterController: SPUStandardUpdaterController

    var body: some View {
        Group {
            Button {
                updateMonitor.showUpdate(using: updaterController.updater)
            } label: {
                Label(
                    updateMonitor.menuTitle,
                    systemImage: "arrow.triangle.2.circlepath"
                )
            }
            .disabled(!updateMonitor.isMenuActionEnabled)

            Button {
                AppInfoService.openGitHubRepository()
            } label: {
                Label(
                    TypeSwitchStrings.Menu.githubRepository,
                    systemImage: "chevron.left.forwardslash.chevron.right"
                )
            }

            Divider()

            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label(TypeSwitchStrings.Menu.quit, systemImage: "power")
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}
