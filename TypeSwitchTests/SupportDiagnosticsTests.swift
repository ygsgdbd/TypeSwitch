import Foundation
@testable import TypeSwitch
import XCTest

final class SupportDiagnosticsTests: XCTestCase {
    func testReportTextWithoutActiveDiagnosticContainsOnlyEnvironmentFields() {
        let diagnostics = SupportDiagnostics(
            version: "1.2.3",
            build: "45",
            operatingSystemVersion: "macOS 15.6 (24G84)",
            architecture: "arm64",
            appLanguage: "zh-Hans",
            localeIdentifier: "en_US"
        )

        XCTAssertEqual(
            diagnostics.reportText,
            """
            Version: 1.2.3
            Build: 45
            macOS: macOS 15.6 (24G84)
            Architecture: arm64
            App Language: zh-Hans
            Locale: en_US
            """
        )
    }

    func testReportTextIncludesActiveDiagnosticWithoutAppOrInputMethodDetails() {
        let diagnostics = SupportDiagnostics(
            version: "1.2.3",
            build: "45",
            operatingSystemVersion: "macOS 15.6 (24G84)",
            architecture: "arm64",
            appLanguage: "zh-Hans",
            localeIdentifier: "zh_Hans_CN",
            diagnosticCategory: "switchFailed",
            errorDescription: "Could not verify the selected input method"
        )

        XCTAssertEqual(
            diagnostics.reportText,
            """
            Version: 1.2.3
            Build: 45
            macOS: macOS 15.6 (24G84)
            Architecture: arm64
            App Language: zh-Hans
            Locale: zh_Hans_CN
            Diagnostic category: switchFailed
            Error description: Could not verify the selected input method
            """
        )
    }

    func testMissingVersionAndBuildUsePlaceholders() {
        let missingVersion = SupportDiagnostics(
            version: nil,
            build: "45",
            operatingSystemVersion: "macOS 15.6 (24G84)",
            architecture: "arm64",
            appLanguage: "en",
            localeIdentifier: "en_US"
        )
        let missingBuild = SupportDiagnostics(
            version: "1.2.3",
            build: "",
            operatingSystemVersion: "macOS 15.6 (24G84)",
            architecture: "arm64",
            appLanguage: "en",
            localeIdentifier: "en_US"
        )

        XCTAssertEqual(missingVersion.version, "–")
        XCTAssertEqual(missingVersion.build, "45")
        XCTAssertTrue(missingVersion.reportText.hasPrefix("Version: –\nBuild: 45\n"))
        XCTAssertEqual(missingBuild.version, "1.2.3")
        XCTAssertEqual(missingBuild.build, "–")
        XCTAssertTrue(missingBuild.reportText.hasPrefix("Version: 1.2.3\nBuild: –\n"))
    }

    func testMissingAppLanguageUsesPlaceholder() {
        let diagnostics = SupportDiagnostics(
            version: "1.2.3",
            build: "45",
            operatingSystemVersion: "macOS 15.6 (24G84)",
            architecture: "arm64",
            appLanguage: nil,
            localeIdentifier: "en_US"
        )

        XCTAssertEqual(diagnostics.appLanguage, "–")
        XCTAssertEqual(diagnostics.localeIdentifier, "en_US")
        XCTAssertTrue(diagnostics.reportText.contains("App Language: –\nLocale: en_US"))
    }

    func testMissingLocaleUsesPlaceholder() {
        let diagnostics = SupportDiagnostics(
            version: "1.2.3",
            build: "45",
            operatingSystemVersion: "macOS 15.6 (24G84)",
            architecture: "arm64",
            appLanguage: "en",
            localeIdentifier: nil
        )

        XCTAssertEqual(diagnostics.localeIdentifier, "–")
        XCTAssertTrue(diagnostics.reportText.contains("App Language: en\nLocale: –"))
    }

    func testReportIssueURLUsesBugReportTemplate() throws {
        let url = try XCTUnwrap(AppInfoService.bugReportURL)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "github.com")
        XCTAssertEqual(components.path, "/ygsgdbd/TypeSwitch/issues/new")
        XCTAssertEqual(
            components.queryItems?.first(where: { $0.name == "template" })?.value,
            "bug_report.yml"
        )
    }
}
