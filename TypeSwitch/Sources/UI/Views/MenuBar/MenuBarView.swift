import AppKit
import ComposableArchitecture
import Sparkle
import SwiftUI

/// 菜单栏主视图
struct MenuBarView: View {
    let store: StoreOf<AppFeature>
    let updaterController: SPUStandardUpdaterController

    var body: some View {
        Group {
            InputMethodDiagnosticsView(store: store)

            if store.inputMethodDiagnostic != nil {
                Divider()
            }

            CurrentAppView(store: store)
            RunningAppsView(store: store)

            if store.currentAppMenuItem != nil
                || !store.runningUnconfiguredMenuItems.isEmpty
                || !store.runningConfiguredMenuItems.isEmpty
            {
                Divider()
            }

            ConfiguredAppsView(store: store)
            UnavailableAppsView(store: store)
            IgnoredAppsView(store: store)
            SwitchStatisticsView(store: store)

            Divider()

            SettingsView(store: store)

            Divider()

            AppInfoView(store: store, updaterController: updaterController)
        }
        .labelStyle(.titleAndIcon)
    }

    static func isRootMenuTrackingNotification(_ notification: Notification) -> Bool {
        guard let menu = notification.object as? NSMenu else {
            return false
        }
        return menu.supermenu == nil && menu !== NSApp.mainMenu
    }
}

private struct InputMethodDiagnosticsView: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        if let diagnostic = store.inputMethodDiagnostic {
            Menu {
                if let appName = diagnostic.appName {
                    Text(TypeSwitchStrings.InputMethodDiagnostics.app(appName))
                }
                if let inputMethodName = diagnostic.inputMethodName {
                    Text(TypeSwitchStrings.InputMethodDiagnostics.target(inputMethodName))
                }
                if let errorDescription = diagnostic.errorDescription {
                    Text(errorDescription)
                }

                Divider()

                switch diagnostic.kind {
                case .catalogEmpty, .catalogFailed:
                    Button {
                        store.send(.view(.reloadInputMethodsTapped))
                    } label: {
                        Label(
                            TypeSwitchStrings.InputMethodDiagnostics.reload,
                            systemImage: "arrow.clockwise"
                        )
                    }
                case .switchFailed:
                    Button {
                        store.send(.view(.retryCurrentAppTapped))
                    } label: {
                        Label(
                            TypeSwitchStrings.InputMethodDiagnostics.retryCurrentApp,
                            systemImage: "arrow.clockwise"
                        )
                    }
                }

                if store.shouldOfferKeyboardSettings {
                    Button(action: openKeyboardSettings) {
                        Label(
                            TypeSwitchStrings.InputMethodDiagnostics.openKeyboardSettings,
                            systemImage: "keyboard"
                        )
                    }
                }
            } label: {
                Label(title(for: diagnostic.kind), systemImage: "exclamationmark.triangle")
            }
        }
    }

    private func title(for kind: AppFeature.State.InputMethodDiagnostic.Kind) -> String {
        switch kind {
        case .catalogEmpty:
            return TypeSwitchStrings.InputMethodDiagnostics.catalogEmpty
        case .catalogFailed:
            return TypeSwitchStrings.InputMethodDiagnostics.catalogFailed
        case .switchFailed:
            return TypeSwitchStrings.InputMethodDiagnostics.switchFailed
        }
    }

    private func openKeyboardSettings() {
        let settingsURLs = [
            "x-apple.systempreferences:com.apple.Keyboard-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.keyboard",
        ]

        for value in settingsURLs {
            guard let url = URL(string: value) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }

        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }
}

private struct CurrentAppView: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        if let item = store.currentAppMenuItem {
            Section(TypeSwitchStrings.Apps.Section.currentApp) {
                AppRowView(
                    item: item,
                    inputMethods: store.inputMethods,
                    onIgnore: {
                        store.send(.view(.ignoreAppTapped(item.appInfo)))
                    }
                ) { strategy in
                    store.send(.view(.setStrategy(bundleId: item.bundleId, strategy: strategy)))
                }
            }
        }
    }
}

#Preview {
    MenuBarView(
        store: Store(initialState: AppFeature.State()) {
            AppFeature()
        },
        updaterController: SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    )
}
