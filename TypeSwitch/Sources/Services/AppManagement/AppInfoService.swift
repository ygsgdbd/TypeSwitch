import AppKit
import Foundation

/// 应用信息服务类，负责管理应用相关链接
enum AppInfoService {
    /// GitHub 仓库信息
    private static let githubRepository = "ygsgdbd/TypeSwitch"
    private static let githubBaseURL = "https://github.com"

    /// 获取 GitHub 仓库 URL
    static var githubRepositoryURL: URL? {
        URL(string: "\(githubBaseURL)/\(githubRepository)")
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
}
