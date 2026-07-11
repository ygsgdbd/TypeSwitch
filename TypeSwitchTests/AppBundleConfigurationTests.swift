import XCTest

@MainActor
final class AppBundleConfigurationTests: XCTestCase {
    func testAppIconProvidesBundledDarkAppearance() throws {
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

        let groups = try XCTUnwrap(configuration["groups"] as? [[String: Any]])
        let layers = try XCTUnwrap(groups.first?["layers"] as? [[String: Any]])
        let layer = try XCTUnwrap(layers.first)
        let defaultImageName = try XCTUnwrap(layer["image-name"] as? String)
        let imageSpecializations = try XCTUnwrap(
            layer["image-name-specializations"] as? [String: String]
        )
        let darkImageName = try XCTUnwrap(imageSpecializations["dark"])

        for imageName in [defaultImageName, darkImageName] {
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

    func testSwiftUIAppDoesNotDeclareMainStoryboard() {
        XCTAssertNil(
            Bundle.main.object(forInfoDictionaryKey: "NSMainStoryboardFile")
        )
    }
}
