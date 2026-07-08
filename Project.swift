import ProjectDescription

// MARK: - Version
let appVersion = Environment.appVersion.getString(default: "0.0.0")
let buildVersion = Environment.buildVersion.getString(default: "0")

let project = Project(
    name: "TypeSwitch",
    options: .options(
        defaultKnownRegions: ["zh-Hans", "zh-Hant", "en"],
        developmentRegion: "zh-Hans"
    ),
    packages: [
        .remote(url: "https://github.com/pointfreeco/swift-case-paths", requirement: .upToNextMajor(from: "1.8.0")),
        .remote(url: "https://github.com/pointfreeco/swift-composable-architecture", requirement: .upToNextMajor(from: "1.26.0")),
        .remote(url: "https://github.com/pointfreeco/swift-dependencies", requirement: .upToNextMajor(from: "1.14.1")),
        .remote(url: "https://github.com/pointfreeco/swift-perception", requirement: .upToNextMajor(from: "2.0.10")),
        .remote(url: "https://github.com/pointfreeco/swift-sharing", requirement: .upToNextMajor(from: "2.9.1")),
        .remote(url: "https://github.com/SwifterSwift/SwifterSwift", requirement: .upToNextMajor(from: "8.0.0"))
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
            deploymentTargets: .macOS("14.0"),
            infoPlist: .extendingDefault(with: [
                "LSUIElement": true,  // 设置为纯菜单栏应用
                "CFBundleDevelopmentRegion": "zh-Hans",  // 设置默认开发区域为简体中文
                "CFBundleLocalizations": ["zh-Hans", "zh-Hant", "en"],  // 支持的语言列表
                "AppleLanguages": ["zh-Hans"],  // 设置默认语言为简体中文
                "NSHumanReadableCopyright": "Copyright © 2024 ygsgdbd. All rights reserved.",
                "LSApplicationCategoryType": "public.app-category.utilities",
                "LSMinimumSystemVersion": "14.0",
                "CFBundleShortVersionString": .string(appVersion),  // 市场版本号
                "CFBundleVersion": .string(buildVersion)  // 构建版本号
            ]),
            sources: ["TypeSwitch/Sources/**"],
            resources: ["TypeSwitch/Resources/**"],
            entitlements: .file(path: "Tuist/Signing/TypeSwitch.entitlements"),
            dependencies: [
                .package(product: "CasePaths"),
                .package(product: "ComposableArchitecture"),
                .package(product: "Dependencies"),
                .package(product: "PerceptionCore"),
                .package(product: "Sharing"),
                .package(product: "SwifterSwift")
            ],
            settings: .settings(
                base: [
                    // 宏定义支持
                    "OTHER_CODE_SIGN_FLAGS": "--deep",
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
        ),
        .target(
            name: "TypeSwitchTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "top.ygsgdbd.TypeSwitchTests",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .default,
            sources: ["TypeSwitchTests/**"],
            dependencies: [
                .package(product: "CasePaths"),
                .target(name: "TypeSwitch"),
                .package(product: "ComposableArchitecture"),
                .package(product: "Dependencies"),
                .package(product: "Sharing")
            ],
            settings: .settings(
                base: [
                    "BUNDLE_LOADER": "$(TEST_HOST)",
                    "SWIFT_VERSION": "5.9",
                    "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/TypeSwitch.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/TypeSwitch",
                    "TEST_TARGET_NAME": "TypeSwitch"
                ],
                configurations: [
                    .debug(name: "Debug"),
                    .release(name: "Release")
                ]
            )
        )
    ]
)
