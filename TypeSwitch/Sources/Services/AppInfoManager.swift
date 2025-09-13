import Foundation
import AppKit
import SwifterSwift

/// 应用信息管理器，负责管理应用版本信息和相关链接
@MainActor
class AppInfoManager: ObservableObject {
    static let shared = AppInfoManager()
    
    /// GitHub 仓库信息
    private let githubRepository = "ygsgdbd/TypeSwitch"
    private let githubBaseURL = "https://github.com"
    
    /// 应用版本信息
    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }
    
    /// 构建版本信息
    var buildVersion: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }
    
    /// 完整版本信息
    var fullVersionInfo: String {
        "v\(appVersion) (\(buildVersion))"
    }
    
    /// GitHub 仓库 URL
    var githubRepositoryURL: URL? {
        URL(string: "\(githubBaseURL)/\(githubRepository)")
    }
    
    /// GitHub Releases 页面 URL
    var githubReleasesURL: URL? {
        URL(string: "\(githubBaseURL)/\(githubRepository)/releases")
    }
    
    /// 最新 Release 页面 URL
    var latestReleaseURL: URL? {
        URL(string: "\(githubBaseURL)/\(githubRepository)/releases/latest")
    }
    
    private init() {}
    
    /// 打开 GitHub 仓库页面
    func openGitHubRepository() {
        guard let url = githubRepositoryURL else { return }
        NSWorkspace.shared.open(url)
    }
    
    /// 打开 GitHub Releases 页面
    func openGitHubReleases() {
        guard let url = githubReleasesURL else { return }
        NSWorkspace.shared.open(url)
    }
    
    /// 打开最新 Release 页面
    func openLatestRelease() {
        guard let url = latestReleaseURL else { return }
        NSWorkspace.shared.open(url)
    }
    
    /// 复制版本信息到剪贴板
    func copyVersionInfo() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(fullVersionInfo, forType: .string)
    }
}
