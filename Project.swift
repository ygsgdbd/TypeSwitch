import ProjectDescription

let project = Project(
    name: "TypeSwitch",
    packages: [
        .remote(url: "https://github.com/sindresorhus/Defaults", requirement: .upToNextMajor(from: "9.0.0")),
        .remote(url: "https://github.com/SwiftUIX/SwiftUIX", requirement: .upToNextMajor(from: "0.1.9")),
    ],
    targets: [
        .target(
            name: "TypeSwitch",
            destinations: .macOS,
            product: .app,
            bundleId: "top.ygsgdbd.TypeSwitch",
            deploymentTargets: .macOS("13.0"),
            infoPlist: .extendingDefault(with: [
                "LSUIElement": true,  // 设置为纯菜单栏应用
                "com.apple.security.app-sandbox": true,
                "com.apple.security.network.client": true,
                "com.apple.security.files.user-selected.read-write": true,
                "com.apple.developer.icloud-container-identifiers": ["iCloud.top.ygsgdbd.TypeSwitch"],
                "com.apple.developer.icloud-services": ["CloudKit"],
                "com.apple.developer.ubiquity-kvstore-identifier": "top.ygsgdbd.TypeSwitch",
                "com.apple.security.application-groups": ["group.top.ygsgdbd.TypeSwitch"],
            ]),
            sources: ["TypeSwitch/Sources/**"],
            resources: ["TypeSwitch/Resources/**"],
            dependencies: [
                .package(product: "Defaults"),
                .package(product: "SwiftUIX"),
            ],
            settings: .settings(base: [
                "ENABLE_APP_SANDBOX": "YES",
                "ENABLE_ICLOUD_SERVICES": "YES",
                "ENABLE_ICLOUD_KEYVALUE_STORAGE": "YES",
            ])
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
