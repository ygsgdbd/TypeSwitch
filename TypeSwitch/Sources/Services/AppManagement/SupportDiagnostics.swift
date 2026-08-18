import Foundation

/// 用户主动复制或报告问题时附带的低敏感环境信息。
struct SupportDiagnostics: Equatable {
    let version: String
    let build: String
    let operatingSystemVersion: String
    let architecture: String
    let appLanguage: String
    let diagnosticCategory: String?
    let errorDescription: String?

    init(
        version: String?,
        build: String?,
        operatingSystemVersion: String,
        architecture: String,
        appLanguage: String?,
        diagnosticCategory: String? = nil,
        errorDescription: String? = nil
    ) {
        self.version = Self.valueOrPlaceholder(version)
        self.build = Self.valueOrPlaceholder(build)
        self.operatingSystemVersion = operatingSystemVersion
        self.architecture = architecture
        self.appLanguage = Self.valueOrPlaceholder(appLanguage)
        self.diagnosticCategory = diagnosticCategory
        self.errorDescription = errorDescription
    }

    static func current(
        diagnosticCategory: String? = nil,
        errorDescription: String? = nil
    ) -> Self {
        let bundle = Bundle.main
        let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildVersion = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        return Self(
            version: shortVersion,
            build: buildVersion,
            operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: currentArchitecture,
            appLanguage: bundle.preferredLocalizations.first,
            diagnosticCategory: diagnosticCategory,
            errorDescription: errorDescription
        )
    }

    var reportText: String {
        var lines = [
            "Version: \(version)",
            "Build: \(build)",
            "macOS: \(operatingSystemVersion)",
            "Architecture: \(architecture)",
            "App Language: \(appLanguage)",
        ]
        if let diagnosticCategory {
            lines.append("Diagnostic category: \(diagnosticCategory)")
        }
        if let errorDescription {
            lines.append("Error description: \(errorDescription)")
        }
        return lines.joined(separator: "\n")
    }

    private static func valueOrPlaceholder(_ value: String?) -> String {
        value.flatMap { $0.isEmpty ? nil : $0 } ?? "–"
    }

    private static var currentArchitecture: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "unknown"
        #endif
    }
}
