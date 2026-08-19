import AppKit
import ComposableArchitecture
import Sparkle
import SwiftUI

/// 应用信息视图，显示项目链接和退出入口
struct AppInfoView: View {
    let store: StoreOf<AppFeature>
    @ObservedObject var updateMonitor: SparkleUpdateMonitor
    let updaterController: SPUStandardUpdaterController

    var body: some View {
        let diagnostics = supportDiagnostics

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

            Menu {
                Button {
                    AppInfoService.openGitHubRepository()
                } label: {
                    Label(
                        TypeSwitchStrings.Support.version(diagnostics.version),
                        systemImage: "chevron.left.forwardslash.chevron.right"
                    )
                }

                Button {
                    AppInfoService.openGitHubProfile()
                } label: {
                    Label(
                        TypeSwitchStrings.Support.developer("ygsgdbd"),
                        systemImage: "person.crop.circle"
                    )
                }

                Divider()

                Button {
                    AppInfoService.openHelp()
                } label: {
                    Label(TypeSwitchStrings.Support.help, systemImage: "questionmark.circle")
                }

                Button {
                    AppInfoService.copySupportDiagnostics(diagnostics)
                } label: {
                    Label(TypeSwitchStrings.Support.copyDiagnostics, systemImage: "doc.on.doc")
                }

                Button {
                    AppInfoService.openReportIssue()
                } label: {
                    Label(TypeSwitchStrings.Support.reportIssue, systemImage: "exclamationmark.bubble")
                }
            } label: {
                Label(
                    TypeSwitchStrings.Support.helpAndAbout,
                    systemImage: "info.circle"
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

    private var supportDiagnostics: SupportDiagnostics {
        let diagnostic = store.inputMethodDiagnostic
        return .current(
            diagnosticCategory: diagnostic.map { category(for: $0.kind) },
            errorDescription: diagnostic?.errorDescription
        )
    }

    private func category(for kind: AppFeature.State.InputMethodDiagnostic.Kind) -> String {
        switch kind {
        case .catalogEmpty:
            return "catalogEmpty"
        case .catalogFailed:
            return "catalogFailed"
        case .switchFailed:
            return "switchFailed"
        }
    }
}
