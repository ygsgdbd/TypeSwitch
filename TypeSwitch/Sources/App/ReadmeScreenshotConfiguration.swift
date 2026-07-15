#if DEBUG
import AppKit
import CoreGraphics
import Foundation
import Sharing
import SwiftUI

struct ReadmeScreenshotConfiguration: Equatable {
    struct Display: Equatable {
        let id: CGDirectDisplayID
        let pixelWidth: Int
        let pixelHeight: Int

        var pixelArea: Int64 {
            Int64(pixelWidth) * Int64(pixelHeight)
        }
    }

    enum Appearance: String, Equatable {
        case light
        case dark
    }

    let appearance: Appearance
    let requestedDisplayID: CGDirectDisplayID?

    var appAppearance: NSAppearance {
        NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)!
    }

    var colorScheme: ColorScheme {
        appearance == .dark ? .dark : .light
    }

    init?(arguments: [String]) {
        guard arguments.contains("--readme-demo") else {
            return nil
        }

        if let optionIndex = arguments.firstIndex(of: "--readme-appearance"),
           arguments.indices.contains(optionIndex + 1),
           let appearance = Appearance(rawValue: arguments[optionIndex + 1])
        {
            self.appearance = appearance
        } else {
            self.appearance = .light
        }

        if let optionIndex = arguments.firstIndex(of: "--readme-display-id"),
           arguments.indices.contains(optionIndex + 1),
           let displayID = CGDirectDisplayID(arguments[optionIndex + 1])
        {
            self.requestedDisplayID = displayID
        } else {
            self.requestedDisplayID = nil
        }
    }

    @MainActor
    func applyAppearance() {
        NSApplication.shared.appearance = appAppearance
    }

    @MainActor
    func applyAppearance(to menu: NSMenu) {
        menu.appearance = appAppearance
        for item in menu.items {
            item.submenu?.appearance = appAppearance
        }
    }

    @MainActor
    func makeBackdropWindow() -> NSWindow? {
        let targetDisplayID = requestedDisplayID
            ?? Self.highestResolutionDisplayID(in: Self.onlineDisplays())
        let screen = NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                as? NSNumber
            else {
                return false
            }
            return number.uint32Value == targetDisplayID
        } ?? NSScreen.main
        guard let screen else { return nil }

        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.appearance = appAppearance
        window.backgroundColor = appearance == .dark
            ? NSColor(srgbRed: 0.08, green: 0.08, blue: 0.09, alpha: 1)
            : NSColor(srgbRed: 0.94, green: 0.95, blue: 0.97, alpha: 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.isOpaque = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.orderFrontRegardless()
        return window
    }

    static func highestResolutionDisplayID(in displays: [Display]) -> CGDirectDisplayID? {
        displays.max { lhs, rhs in
            if lhs.pixelArea != rhs.pixelArea {
                return lhs.pixelArea < rhs.pixelArea
            }
            if lhs.pixelWidth != rhs.pixelWidth {
                return lhs.pixelWidth < rhs.pixelWidth
            }
            return lhs.id < rhs.id
        }?.id
    }

    func initialState(now: Date) -> AppFeature.State {
        let abcID = "com.apple.keylayout.ABC"
        let pinyinID = "com.apple.inputmethod.SCIM.ITABC"
        let safari = AppInfo(
            bundleId: "com.apple.Safari",
            name: "Safari",
            path: "/Applications/Safari.app"
        )
        let notes = AppInfo(
            bundleId: "com.apple.Notes",
            name: "Notes",
            path: "/System/Applications/Notes.app"
        )
        let terminal = AppInfo(
            bundleId: "com.apple.Terminal",
            name: "Terminal",
            path: "/System/Applications/Utilities/Terminal.app"
        )
        let rules = [
            safari.bundleId: AppRuleRecord(
                bundleId: safari.bundleId,
                lastKnownPath: safari.path,
                lastKnownName: safari.name,
                strategy: .fixed(inputMethodId: pinyinID),
                createdAt: now,
                updatedAt: now
            ),
            terminal.bundleId: AppRuleRecord(
                bundleId: terminal.bundleId,
                lastKnownPath: terminal.path,
                lastKnownName: terminal.name,
                strategy: .fixed(inputMethodId: abcID),
                createdAt: now,
                updatedAt: now
            ),
            "com.example.LegacyEditor": AppRuleRecord(
                bundleId: "com.example.LegacyEditor",
                lastKnownPath: nil,
                lastKnownName: "Legacy Editor",
                strategy: .fixed(inputMethodId: "com.example.missing-input-method"),
                createdAt: now,
                updatedAt: now
            ),
        ]

        return AppFeature.State(
            appRulesStore: Shared(value: AppRulesStore(rules: rules)),
            appSwitchStatisticsStore: Shared(
                value: AppSwitchStatisticsStore(
                    counts: [
                        safari.bundleId: 18,
                        terminal.bundleId: 33,
                    ]
                )
            ),
            fallbackRuleStore: Shared(
                value: FallbackRuleStore(strategy: .fixed(inputMethodId: abcID))
            ),
            currentFrontmostBundleId: safari.bundleId,
            inputMethods: [
                InputMethod(id: abcID, name: "ABC"),
                InputMethod(id: pinyinID, name: "Pinyin"),
            ],
            isReadmeDemo: true,
            launchAtLoginStatus: .enabled,
            runningApps: [safari, notes, terminal]
        )
    }

    private static func onlineDisplays() -> [Display] {
        var displayCount: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &displayCount) == .success,
              displayCount > 0
        else {
            return []
        }

        var displayIDs = Array(repeating: CGDirectDisplayID(), count: Int(displayCount))
        guard CGGetOnlineDisplayList(displayCount, &displayIDs, &displayCount) == .success else {
            return []
        }

        return displayIDs.prefix(Int(displayCount)).map { displayID in
            let displayMode = CGDisplayCopyDisplayMode(displayID)
            return Display(
                id: displayID,
                pixelWidth: displayMode?.pixelWidth ?? CGDisplayPixelsWide(displayID),
                pixelHeight: displayMode?.pixelHeight ?? CGDisplayPixelsHigh(displayID)
            )
        }
    }
}
#endif
