import ProjectDescription

let project = Project(
    name: "TypeSwitch",
    options: .options(
        defaultKnownRegions: ["zh-Hans", "zh-Hant", "en"],
        developmentRegion: "zh-Hans"
    ),
    packages: [
        .remote(url: "https://github.com/sindresorhus/Defaults", requirement: .upToNextMajor(from: "9.0.0")),
        .remote(url: "https://github.com/SwiftUIX/SwiftUIX", requirement: .upToNextMajor(from: "0.1.9")),
        .remote(url: "https://github.com/SwifterSwift/SwifterSwift", requirement: .upToNextMajor(from: "7.0.0")),
        .remote(url: "https://github.com/sindresorhus/KeyboardShortcuts", requirement: .upToNextMajor(from: "2.2.2"))
    ],
    settings: .settings(
        base: [
            "SWIFT_VERSION": "5.9",
            "DEVELOPMENT_LANGUAGE": "zh-Hans",
            "SWIFT_EMIT_LOC_STRINGS": "YES"
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
                "NSHumanReadableCopyright": "Copyright © 2024 ygsgdbd. All rights reserved."
            ]),
            sources: ["TypeSwitch/Sources/**"],
            resources: [
                "TypeSwitch/Resources/**",
                .folderReference(path: "TypeSwitch/Resources/zh-Hans.lproj"),
                .folderReference(path: "TypeSwitch/Resources/zh-Hant.lproj"),
                .folderReference(path: "TypeSwitch/Resources/en.lproj")
            ],
            dependencies: [
                .package(product: "Defaults"),
                .package(product: "SwiftUIX"),
                .package(product: "SwifterSwift"),
                .package(product: "KeyboardShortcuts")
            ],
            settings: .settings(
                base: [
                    "DEVELOPMENT_LANGUAGE": "zh-Hans",
                    "SWIFT_VERSION": "5.9",
                    "SWIFT_EMIT_LOC_STRINGS": "YES"
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
            deploymentTargets: .macOS("13.0"),
            infoPlist: .default,
            sources: ["TypeSwitch/Tests/**"],
            resources: [],
            dependencies: [.target(name: "TypeSwitch")]
        ),
    ]
)
