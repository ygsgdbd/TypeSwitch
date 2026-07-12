import AppKit
import Sparkle
import SwiftUI

/// 应用信息视图，显示项目链接和退出入口
struct AppInfoView: View {
    let updaterController: SPUStandardUpdaterController

    var body: some View {
        Group {
            Section {
                Button {
                    updaterController.checkForUpdates(nil)
                } label: {
                    Label(
                        TypeSwitchStrings.Settings.General.checkForUpdates,
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                }

                Button {
                    AppInfoService.openGitHubRepository()
                } label: {
                    Label(TypeSwitchStrings.Menu.githubRepository, systemImage: "link")
                }
            }

            Divider()

            Section {
                Button(role: .destructive) {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label(TypeSwitchStrings.Menu.quit, systemImage: "power")
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }
    }
}
