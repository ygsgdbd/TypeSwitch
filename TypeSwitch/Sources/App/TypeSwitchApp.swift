import AppKit
import ComposableArchitecture
import Sparkle
import SwiftUI

@main
struct TypeSwitchApp: App {
    let menuTrackingObservers: [NSObjectProtocol]
    let readmeBackdropWindow: NSWindow?
    let readmeColorScheme: ColorScheme?
    let store: StoreOf<AppFeature>
    let updaterController: SPUStandardUpdaterController

    init() {
        #if DEBUG
        let readmeConfiguration = ReadmeScreenshotConfiguration(
            arguments: ProcessInfo.processInfo.arguments
        )
        readmeConfiguration?.applyAppearance()
        let readmeMenuAppearance = readmeConfiguration?.appAppearance
        self.readmeBackdropWindow = readmeConfiguration?.makeBackdropWindow()
        self.readmeColorScheme = readmeConfiguration?.colorScheme
        let initialState = readmeConfiguration?.initialState(now: Date()) ?? AppFeature.State()
        let startsLiveServices = readmeConfiguration == nil
        #else
        let readmeMenuAppearance: NSAppearance? = nil
        self.readmeBackdropWindow = nil
        self.readmeColorScheme = nil
        let initialState = AppFeature.State()
        let startsLiveServices = true
        #endif
        let store = Store(initialState: initialState) {
            AppFeature()
        }
        self.store = store
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: startsLiveServices,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        if let readmeMenuAppearance {
            self.menuTrackingObservers = [
                NotificationCenter.default.addObserver(
                    forName: NSMenu.didBeginTrackingNotification,
                    object: nil,
                    queue: .main
                ) { notification in
                    MainActor.assumeIsolated {
                        guard let menu = notification.object as? NSMenu else { return }
                        menu.appearance = readmeMenuAppearance
                        for item in menu.items {
                            item.submenu?.appearance = readmeMenuAppearance
                        }
                    }
                },
            ]
        } else {
            self.menuTrackingObservers = []
        }
        if startsLiveServices {
            store.send(.task)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(store: store, updaterController: updaterController)
                .preferredColorScheme(readmeColorScheme)
        } label: {
            MenuBarIconView(store: store)
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MenuBarIconView: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        Image(systemName: store.menuBarIconSystemName)
            .accessibilityLabel("TypeSwitch")
    }
}
