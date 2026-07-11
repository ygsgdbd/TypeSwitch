import XCTest

@MainActor
final class AppBundleConfigurationTests: XCTestCase {
    func testSwiftUIAppDoesNotDeclareMainStoryboard() {
        XCTAssertNil(
            Bundle.main.object(forInfoDictionaryKey: "NSMainStoryboardFile")
        )
    }
}
