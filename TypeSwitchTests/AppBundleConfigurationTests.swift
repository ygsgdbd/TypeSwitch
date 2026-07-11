import XCTest

@MainActor
final class AppBundleConfigurationTests: XCTestCase {
    func testAppIconProvidesBundledAppearanceVariants() throws {
        let repositoryRootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appIconURL = repositoryRootURL
            .appendingPathComponent("TypeSwitch/Resources/AppIcon.icon")
        let configurationURL = appIconURL.appendingPathComponent("icon.json")

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: configurationURL.path),
            "The bundled AppIcon.icon configuration must exist."
        )

        let data = try Data(contentsOf: configurationURL)
        let configuration = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let fillSpecializations = try XCTUnwrap(
            configuration["fill-specializations"] as? [String: Any]
        )
        XCTAssertNotNil(fillSpecializations["dark"])
        XCTAssertNotNil(fillSpecializations["tinted"])

        let groups = try XCTUnwrap(configuration["groups"] as? [[String: Any]])
        let layers = try XCTUnwrap(groups.first?["layers"] as? [[String: Any]])
        let layer = try XCTUnwrap(layers.first)
        let defaultImageName = try XCTUnwrap(layer["image-name"] as? String)
        let imageSpecializations = try XCTUnwrap(
            layer["image-name-specializations"] as? [String: String]
        )
        let darkImageName = try XCTUnwrap(imageSpecializations["dark"])
        let tintedImageName = try XCTUnwrap(imageSpecializations["tinted"])

        for imageName in [defaultImageName, darkImageName, tintedImageName] {
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: appIconURL.appendingPathComponent("Assets/\(imageName)").path
                ),
                "The AppIcon.icon image \(imageName) must exist."
            )
        }

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: repositoryRootURL
                    .appendingPathComponent("TypeSwitch/Resources/Assets.xcassets/AppIcon.appiconset")
                    .path
            ),
            "The legacy AppIcon.appiconset must not conflict with AppIcon.icon."
        )
    }

    func testReadmesUseGeneratedAdaptiveAppIconPreviews() throws {
        let repositoryRootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let previewDirectoryURL = repositoryRootURL
            .appendingPathComponent("Design/AppIcon/Previews")
        let defaultPreviewName = "typeswitch-icon-default.png"
        let darkPreviewName = "typeswitch-icon-dark.png"

        for previewName in [defaultPreviewName, darkPreviewName] {
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: previewDirectoryURL.appendingPathComponent(previewName).path
                ),
                "The generated README preview \(previewName) must exist."
            )
        }

        for readmeName in ["README.md", "README.zh-CN.md"] {
            let readmeURL = repositoryRootURL.appendingPathComponent(readmeName)
            let contents = try String(contentsOf: readmeURL, encoding: .utf8)

            XCTAssertTrue(contents.contains("Design/AppIcon/Previews/\(defaultPreviewName)"))
            XCTAssertTrue(contents.contains("Design/AppIcon/Previews/\(darkPreviewName)"))
            XCTAssertFalse(contents.contains("Design/AppIcon/type-switch-keyboard"))
        }
    }

    func testSwiftUIAppDoesNotDeclareMainStoryboard() {
        XCTAssertNil(
            Bundle.main.object(forInfoDictionaryKey: "NSMainStoryboardFile")
        )
    }
}
