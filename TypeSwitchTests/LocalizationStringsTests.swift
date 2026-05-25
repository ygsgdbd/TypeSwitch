import Foundation
import XCTest

final class LocalizationStringsTests: XCTestCase {
    func testLocalizableStringFilesHaveMatchingKeys() throws {
        let resourcesURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "TypeSwitch/Resources", directoryHint: .isDirectory)
        let localizations = ["Base", "zh-Hans", "zh-Hant", "en"]
        let keySets = try Dictionary(uniqueKeysWithValues: localizations.map { localization in
            let fileURL = resourcesURL
                .appending(path: "\(localization).lproj", directoryHint: .isDirectory)
                .appending(path: "Localizable.strings")
            return (localization, try Self.keys(in: fileURL))
        })
        let referenceKeys = try XCTUnwrap(keySets["Base"])

        for localization in localizations.dropFirst() {
            let localizationKeys = try XCTUnwrap(keySets[localization])
            XCTAssertEqual(
                localizationKeys,
                referenceKeys,
                "\(localization).lproj/Localizable.strings keys differ from Base"
            )
        }
    }

    private static func keys(in fileURL: URL) throws -> Set<String> {
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let keyPattern = #"^\s*"([^"]+)"\s*="#
        let regex = try NSRegularExpression(pattern: keyPattern, options: [.anchorsMatchLines])
        let range = NSRange(content.startIndex..<content.endIndex, in: content)

        return Set(regex.matches(in: content, range: range).compactMap { match in
            guard let keyRange = Range(match.range(at: 1), in: content) else {
                return nil
            }
            return String(content[keyRange])
        })
    }
}
