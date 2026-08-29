import AppKit
import Foundation

/// 应用信息服务类，负责管理应用相关链接
enum AppInfoService {
    /// GitHub 仓库信息
    private static let githubAccount = "ygsgdbd"
    private static let githubRepository = "\(githubAccount)/TypeSwitch"
    private static let githubBaseURL = "https://github.com"

    /// 获取开发者 GitHub 主页 URL
    static var githubProfileURL: URL? {
        URL(string: "\(githubBaseURL)/\(githubAccount)")
    }

    /// 获取 GitHub 仓库 URL
    static var githubRepositoryURL: URL? {
        URL(string: "\(githubBaseURL)/\(githubRepository)")
    }

    /// 获取 GitHub Releases 页面 URL
    static var githubReleasesURL: URL? {
        URL(string: "\(githubBaseURL)/\(githubRepository)/releases")
    }

    /// 获取使用帮助页面 URL
    static var helpURL: URL? {
        URL(string: "\(githubBaseURL)/\(githubRepository)#readme")
    }

    /// 获取 GitHub Bug Report 表单 URL
    static var bugReportURL: URL? {
        guard var components = URLComponents(
            string: "\(githubBaseURL)/\(githubRepository)/issues/new"
        ) else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "template", value: "bug_report.yml"),
        ]
        return components.url
    }

    /// 打开 GitHub 仓库页面
    @MainActor
    static func openGitHubRepository() {
        guard let url = githubRepositoryURL else { return }
        NSWorkspace.shared.open(url)
    }

    /// 打开开发者 GitHub 主页
    @MainActor
    static func openGitHubProfile() {
        guard let url = githubProfileURL else { return }
        NSWorkspace.shared.open(url)
    }

    /// 打开 GitHub Releases 页面
    @MainActor
    static func openGitHubReleases() {
        guard let url = githubReleasesURL else { return }
        NSWorkspace.shared.open(url)
    }

    /// 打开使用帮助页面
    @MainActor
    static func openHelp() {
        guard let url = helpURL else { return }
        NSWorkspace.shared.open(url)
    }

    /// 复制低敏感诊断信息
    @MainActor
    static func copySupportDiagnostics(_ diagnostics: SupportDiagnostics) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnostics.reportText, forType: .string)
    }

    /// 打开 GitHub Issue 页面
    @MainActor
    static func openReportIssue() {
        guard let url = bugReportURL else { return }
        NSWorkspace.shared.open(url)
    }
}
