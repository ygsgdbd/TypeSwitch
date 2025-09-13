import Foundation
import AppKit
import SwifterSwift

/// 应用信息管理工具，负责管理应用版本信息和相关链接
enum AppInfoManager {
    /// GitHub 仓库信息
    private static let githubRepository = "ygsgdbd/TypeSwitch"
    private static let githubBaseURL = "https://github.com"
    
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
    
    /// 获取 GitHub 仓库 URL
    static var githubRepositoryURL: URL? {
        URL(string: "\(githubBaseURL)/\(githubRepository)")
    }
    
    /// 获取 GitHub Releases 页面 URL
    static var githubReleasesURL: URL? {
        URL(string: "\(githubBaseURL)/\(githubRepository)/releases")
    }
    
    /// 获取最新 Release 页面 URL
    static var latestReleaseURL: URL? {
        URL(string: "\(githubBaseURL)/\(githubRepository)/releases/latest")
    }
    
    /// 打开 GitHub 仓库页面
    static func openGitHubRepository() {
        guard let url = githubRepositoryURL else { return }
        NSWorkspace.shared.open(url)
    }
    
    /// 打开 GitHub Releases 页面
    static func openGitHubReleases() {
        guard let url = githubReleasesURL else { return }
        NSWorkspace.shared.open(url)
    }
    
    /// 打开最新 Release 页面
    static func openLatestRelease() {
        guard let url = latestReleaseURL else { return }
        NSWorkspace.shared.open(url)
    }
    
    /// 复制版本信息到剪贴板
    static func copyVersionInfo() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(fullVersionInfo, forType: .string)
    }
}
