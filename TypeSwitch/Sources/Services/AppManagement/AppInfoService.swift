import Foundation
import AppKit
import SwiftUI
import SwifterSwift

/// 应用信息服务类，负责管理应用版本信息和相关链接
enum AppInfoService {
    /// GitHub 仓库信息
    private static let githubRepository = "ygsgdbd/TypeSwitch"
    private static let githubBaseURL = "https://github.com"
    private static let licenseName = "MIT"
    @MainActor
    private static var aboutWindowController: NSWindowController?

    /// 获取应用版本信息
    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    /// 获取构建版本信息
    static var buildVersion: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }

    /// 获取完整版本信息
    static var fullVersionInfo: String {
        "v\(appVersion) (\(buildVersion))"
    }

    /// 获取版权信息
    static var copyright: String {
        Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String
            ?? "Copyright © 2024 ygsgdbd. All rights reserved."
    }

    /// 获取 GitHub 仓库 URL
    static var githubRepositoryURL: URL? {
        URL(string: "\(githubBaseURL)/\(githubRepository)")
    }

    /// 获取 GitHub 仓库显示名称
    static var githubRepositoryDisplayName: String {
        "github.com/\(githubRepository)"
    }

    /// 获取 GitHub Releases 页面 URL
    static var githubReleasesURL: URL? {
        URL(string: "\(githubBaseURL)/\(githubRepository)/releases")
    }

    /// 打开 GitHub 仓库页面
    @MainActor
    static func openGitHubRepository() {
        guard let url = githubRepositoryURL else { return }
        NSWorkspace.shared.open(url)
    }

    /// 打开 GitHub Releases 页面
    @MainActor
    static func openGitHubReleases() {
        guard let url = githubReleasesURL else { return }
        NSWorkspace.shared.open(url)
    }

    /// 打开关于窗口
    @MainActor
    static func openAboutWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)

        let windowController: NSWindowController
        if let existingWindowController = aboutWindowController {
            windowController = existingWindowController
        } else {
            let aboutView = AboutWindowView(
                appVersion: fullVersionInfo,
                repositoryDisplayName: githubRepositoryDisplayName,
                licenseName: licenseName,
                copyright: copyright,
                openRepository: openGitHubRepository,
                closeWindow: closeAboutWindow
            )
            let hostingController = NSHostingController(rootView: aboutView)
            let window = NSWindow(contentViewController: hostingController)
            window.title = TypeSwitchStrings.App.about
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 380, height: 320))
            window.minSize = NSSize(width: 380, height: 320)
            window.maxSize = NSSize(width: 380, height: 320)
            window.isReleasedWhenClosed = false
            window.center()

            windowController = NSWindowController(window: window)
            aboutWindowController = windowController
        }

        if let window = windowController.window {
            if !window.isVisible {
                window.center()
            }
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    /// 关闭关于窗口
    @MainActor
    static func closeAboutWindow() {
        aboutWindowController?.close()
    }

    /// 复制版本信息到剪贴板
    static func copyVersionInfo() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(fullVersionInfo, forType: .string)
    }
}
