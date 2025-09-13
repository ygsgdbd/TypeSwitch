import ProjectDescription

// MARK: - Version
let appVersion = "0.3.5"  // 应用版本号
let buildVersion = "@BUILD_NUMBER@"  // 构建版本号占位符，会被 GitHub Actions 替换

let project = Project(
    name: "TypeSwitch",
    options: .options(
        defaultKnownRegions: ["zh-Hans", "zh-Hant", "en"],
        developmentRegion: "zh-Hans"
    ),
    packages: [
        .remote(url: "https://github.com/SwiftUIX/SwiftUIX", requirement: .upToNextMajor(from: "0.2.3")),
        .remote(url: "https://github.com/SwifterSwift/SwifterSwift", requirement: .upToNextMajor(from: "8.0.0")),
        .remote(url: "https://github.com/sindresorhus/Defaults", requirement: .upToNextMajor(from: "9.0.3")),
        .remote(url: "https://github.com/pointfreeco/swift-perception", requirement: .upToNextMajor(from: "2.0.7"))
    ],
    settings: .settings(
        base: [
            "SWIFT_VERSION": SettingValue(stringLiteral: "5.9"),
            "DEVELOPMENT_LANGUAGE": SettingValue(stringLiteral: "zh-Hans"),
            "SWIFT_EMIT_LOC_STRINGS": SettingValue(stringLiteral: "YES"),
            "MARKETING_VERSION": SettingValue(stringLiteral: appVersion),
            "CURRENT_PROJECT_VERSION": SettingValue(stringLiteral: buildVersion),
            // 宏定义支持
            "SWIFT_STRICT_CONCURRENCY": SettingValue(stringLiteral: "complete"),
            "ENABLE_MACROS": SettingValue(stringLiteral: "YES"),
            "SWIFT_MACRO_DEBUGGING": SettingValue(stringLiteral: "YES")
        ],
        configurations: [
            .debug(name: "Debug"),
            .release(name: "Release")
        ]
    ),
    targets: [
        .target(
            name: "TypeSwitch",
            destinations: .macOS,
            product: .app,
            bundleId: "top.ygsgdbd.TypeSwitch",
            deploymentTargets: .macOS("13.0"),
            infoPlist: .extendingDefault(with: [
                "LSUIElement": true,  // 设置为纯菜单栏应用
                "CFBundleDevelopmentRegion": "zh-Hans",  // 设置默认开发区域为简体中文
                "CFBundleLocalizations": ["zh-Hans", "zh-Hant", "en"],  // 支持的语言列表
                "AppleLanguages": ["zh-Hans"],  // 设置默认语言为简体中文
                "NSHumanReadableCopyright": "Copyright © 2024 ygsgdbd. All rights reserved.",
                "LSApplicationCategoryType": "public.app-category.utilities",
                "LSMinimumSystemVersion": "13.0",
                "CFBundleShortVersionString": .string(appVersion),  // 市场版本号
                "CFBundleVersion": .string(buildVersion)  // 构建版本号
            ]),
            sources: ["TypeSwitch/Sources/**"],
            resources: ["TypeSwitch/Resources/**"],
            entitlements: .file(path: "Tuist/Signing/TypeSwitch.entitlements"),
            dependencies: [
                .package(product: "SwiftUIX"),
                .package(product: "SwifterSwift"),
                .package(product: "Defaults"),
                .package(product: "Perception")
            ],
            settings: .settings(
                base: [
                    // 宏定义支持
                    "SWIFT_STRICT_CONCURRENCY": "complete",
                    "ENABLE_MACROS": "YES",
                    "SWIFT_MACRO_DEBUGGING": "YES",
                    "SWIFT_MACRO_EXPANSION": "YES"
                ],
                configurations: [
                    .debug(name: "Debug"),
                    .release(name: "Release")
                ]
            )
        )
    ]
)
