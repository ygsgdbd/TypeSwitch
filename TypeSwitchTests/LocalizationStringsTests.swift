import Foundation
import XCTest

final class LocalizationStringsTests: XCTestCase {
    func testLocalizableStringFilesHaveMatchingKeys() throws {
        let keySets = try Dictionary(uniqueKeysWithValues: Self.localizations.map { localization in
            return (localization, try Self.keys(in: Self.fileURL(for: localization)))
        })
        let referenceKeys = try XCTUnwrap(keySets["Base"])

        for localization in Self.localizations.dropFirst() {
            let localizationKeys = try XCTUnwrap(keySets[localization])
            XCTAssertEqual(
                localizationKeys,
                referenceKeys,
                "\(localization).lproj/Localizable.strings keys differ from Base"
            )
        }
    }

    func testLocalizableStringFilesHaveMatchingPlaceholders() throws {
        let localizedStrings = try Dictionary(uniqueKeysWithValues: Self.localizations.map { localization in
            return (localization, try Self.strings(in: Self.fileURL(for: localization)))
        })
        let referenceStrings = try XCTUnwrap(localizedStrings["Base"])

        for localization in Self.localizations.dropFirst() {
            let strings = try XCTUnwrap(localizedStrings[localization])
            for key in referenceStrings.keys {
                let referenceValue = try XCTUnwrap(referenceStrings[key])
                let localizedValue = try XCTUnwrap(strings[key])
                XCTAssertEqual(
                    try Self.placeholders(in: localizedValue),
                    try Self.placeholders(in: referenceValue),
                    "\(localization).lproj/Localizable.strings placeholder signature differs for \(key)"
                )
            }
        }
    }

    func testMenuCopyMatchesSharedAppConventions() throws {
        let expectedValues: [String: [String: String]] = [
            "Base": [
                "menu.github_repository": "GitHub 仓库",
                "settings.general.auto_launch": "登录时打开",
                "settings.general.auto_launch_requires_approval": "请前往“系统设置”>“通用”>“登录项”允许 TypeSwitch。",
                "settings.general.open_login_items": "打开登录项设置",
                "settings.general.check_for_updates": "检查更新…",
                "settings.general.update_available": "发现新版本…",
                "settings.fallback.default_input_method": "未配置 App 的默认规则",
                "apps.section.running_count": "运行中 · 已配置（%d）",
                "apps.section.unconfigured_count": "运行中 · 未配置（%d）",
                "apps.section.configured_count": "全部已配置 App（%d）",
                "apps.section.unavailable_count": "找不到的 App（%d）",
                "apps.ignore": "忽略此 App",
                "apps.ignored.menu_title": "已忽略 App（%d）",
                "apps.ignored.restore_hint": "选择 App 以恢复",
                "apps.ignored.restore_all": "恢复全部",
                "apps.clear_unavailable": "清理找不到的 App",
                "apps.clear_unavailable_confirmation.title": "清理找不到的 App？",
                "switch_statistics.menu_title": "切换统计（%d 次）",
                "input_method.clear_missing_confirmation.message": "失效项会改为跟随未配置 App 的默认规则。",
            ],
            "zh-Hans": [
                "menu.github_repository": "GitHub 仓库",
                "settings.general.auto_launch": "登录时打开",
                "settings.general.auto_launch_requires_approval": "请前往“系统设置”>“通用”>“登录项”允许 TypeSwitch。",
                "settings.general.open_login_items": "打开登录项设置",
                "settings.general.check_for_updates": "检查更新…",
                "settings.general.update_available": "发现新版本…",
                "settings.fallback.default_input_method": "未配置 App 的默认规则",
                "apps.section.running_count": "运行中 · 已配置（%d）",
                "apps.section.unconfigured_count": "运行中 · 未配置（%d）",
                "apps.section.configured_count": "全部已配置 App（%d）",
                "apps.section.unavailable_count": "找不到的 App（%d）",
                "apps.ignore": "忽略此 App",
                "apps.ignored.menu_title": "已忽略 App（%d）",
                "apps.ignored.restore_hint": "选择 App 以恢复",
                "apps.ignored.restore_all": "恢复全部",
                "apps.clear_unavailable": "清理找不到的 App",
                "apps.clear_unavailable_confirmation.title": "清理找不到的 App？",
                "switch_statistics.menu_title": "切换统计（%d 次）",
                "input_method.clear_missing_confirmation.message": "失效项会改为跟随未配置 App 的默认规则。",
            ],
            "zh-Hant": [
                "menu.github_repository": "GitHub 儲存庫",
                "settings.general.auto_launch": "登入時開啟",
                "settings.general.auto_launch_requires_approval": "請前往「系統設定」>「一般」>「登入項目」允許 TypeSwitch。",
                "settings.general.open_login_items": "開啟登入項目設定",
                "settings.general.check_for_updates": "檢查更新…",
                "settings.general.update_available": "發現新版本…",
                "settings.fallback.default_input_method": "未設定 App 的預設規則",
                "apps.section.running_count": "執行中 · 已設定（%d）",
                "apps.section.unconfigured_count": "執行中 · 未設定（%d）",
                "apps.section.configured_count": "全部已設定 App（%d）",
                "apps.section.unavailable_count": "找不到的 App（%d）",
                "apps.ignore": "忽略此 App",
                "apps.ignored.menu_title": "已忽略 App（%d）",
                "apps.ignored.restore_hint": "選擇 App 以恢復",
                "apps.ignored.restore_all": "恢復全部",
                "apps.clear_unavailable": "清理找不到的 App",
                "apps.clear_unavailable_confirmation.title": "清理找不到的 App？",
                "switch_statistics.menu_title": "切換統計（%d 次）",
                "input_method.clear_missing_confirmation.message": "失效項會改為跟隨未設定 App 的預設規則。",
            ],
            "en": [
                "menu.github_repository": "GitHub Repository",
                "settings.general.auto_launch": "Launch at Login",
                "settings.general.auto_launch_requires_approval": "Approve TypeSwitch in System Settings > General > Login Items.",
                "settings.general.open_login_items": "Open Login Items Settings",
                "settings.general.check_for_updates": "Check for Updates…",
                "settings.general.update_available": "New Version Available…",
                "settings.fallback.default_input_method": "Default Rule for Unconfigured Apps",
                "apps.section.running_count": "Running · Configured (%d)",
                "apps.section.unconfigured_count": "Running · Unconfigured (%d)",
                "apps.section.configured_count": "All Configured Apps (%d)",
                "apps.section.unavailable_count": "Missing Apps (%d)",
                "apps.ignore": "Ignore This App",
                "apps.ignored.menu_title": "Ignored Apps (%d)",
                "apps.ignored.restore_hint": "Select an app to restore",
                "apps.ignored.restore_all": "Restore All",
                "apps.clear_unavailable": "Clear Missing Apps",
                "apps.clear_unavailable_confirmation.title": "Clear missing apps?",
                "switch_statistics.menu_title": "Switches (%d)",
                "input_method.clear_missing_confirmation.message": "Unavailable items will use the Default Rule for Unconfigured Apps.",
            ],
        ]

        for localization in Self.localizations {
            let strings = try Self.strings(in: Self.fileURL(for: localization))
            let expected = try XCTUnwrap(expectedValues[localization])

            for (key, value) in expected {
                XCTAssertEqual(strings[key], value, "Unexpected value for \(localization).lproj key \(key)")
            }
        }
    }

    private static let localizations = ["Base", "zh-Hans", "zh-Hant", "en"]

    private static var resourcesURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "TypeSwitch/Resources", directoryHint: .isDirectory)
    }

    private static func fileURL(for localization: String) -> URL {
        resourcesURL
            .appending(path: "\(localization).lproj", directoryHint: .isDirectory)
            .appending(path: "Localizable.strings")
    }

    private static func strings(in fileURL: URL) throws -> [String: String] {
        let data = try Data(contentsOf: fileURL)
        let propertyList = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try XCTUnwrap(propertyList as? [String: String])
    }

    private static func keys(in fileURL: URL) throws -> Set<String> {
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let keyPattern = #"^\s*"([^"]+)"\s*="#
        let regex = try NSRegularExpression(pattern: keyPattern, options: [.anchorsMatchLines])
        let range = NSRange(content.startIndex ..< content.endIndex, in: content)

        return Set(regex.matches(in: content, range: range).compactMap { match in
            guard let keyRange = Range(match.range(at: 1), in: content) else {
                return nil
            }
            return String(content[keyRange])
        })
    }

    private static func placeholders(in value: String) throws -> [String] {
        let pattern = #"%[@d]"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(value.startIndex ..< value.endIndex, in: value)

        return regex.matches(in: value, range: range).compactMap { match in
            guard let placeholderRange = Range(match.range, in: value) else {
                return nil
            }
            return String(value[placeholderRange])
        }
    }
}
