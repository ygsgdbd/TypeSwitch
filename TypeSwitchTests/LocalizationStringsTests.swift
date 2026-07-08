import Foundation
import XCTest

final class LocalizationStringsTests: XCTestCase {
    func testLocalizableStringFilesHaveMatchingKeys() throws {
        let keySets = try Dictionary(uniqueKeysWithValues: Self.localizations.map { localization in
            return (localization, try Self.keys(in: Self.fileURL(for: localization)))
        })
        let referenceKeys = try XCTUnwrap(keySets["Base"])

        for localization in Self.localizations.dropFirst() {
            let localizationKeys = try XCTUnwrap(keySets[localization])
            XCTAssertEqual(
                localizationKeys,
                referenceKeys,
                "\(localization).lproj/Localizable.strings keys differ from Base"
            )
        }
    }

    func testLocalizableStringFilesHaveMatchingPlaceholders() throws {
        let localizedStrings = try Dictionary(uniqueKeysWithValues: Self.localizations.map { localization in
            return (localization, try Self.strings(in: Self.fileURL(for: localization)))
        })
        let referenceStrings = try XCTUnwrap(localizedStrings["Base"])

        for localization in Self.localizations.dropFirst() {
            let strings = try XCTUnwrap(localizedStrings[localization])
            for key in referenceStrings.keys {
                let referenceValue = try XCTUnwrap(referenceStrings[key])
                let localizedValue = try XCTUnwrap(strings[key])
                XCTAssertEqual(
                    try Self.placeholders(in: localizedValue),
                    try Self.placeholders(in: referenceValue),
                    "\(localization).lproj/Localizable.strings placeholder signature differs for \(key)"
                )
            }
        }
    }

    private static let localizations = ["Base", "zh-Hans", "zh-Hant", "en"]

    private static var resourcesURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "TypeSwitch/Resources", directoryHint: .isDirectory)
    }

    private static func fileURL(for localization: String) -> URL {
        resourcesURL
            .appending(path: "\(localization).lproj", directoryHint: .isDirectory)
            .appending(path: "Localizable.strings")
    }

    private static func strings(in fileURL: URL) throws -> [String: String] {
        let data = try Data(contentsOf: fileURL)
        let propertyList = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try XCTUnwrap(propertyList as? [String: String])
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

    private static func placeholders(in value: String) throws -> [String] {
        let pattern = #"%[@d]"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(value.startIndex..<value.endIndex, in: value)

        return regex.matches(in: value, range: range).compactMap { match in
            guard let placeholderRange = Range(match.range, in: value) else {
                return nil
            }
            return String(value[placeholderRange])
        }
    }
}
