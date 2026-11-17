import Foundation
import ServiceManagement
@testable import TypeSwitch
import XCTest

final class LaunchAtLoginServiceTests: XCTestCase {
    func testStatusUsesFallbackLaunchAgentWhenExecutableMatches() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.writeLaunchAgent(executablePath: fixture.executableURL.path)

        XCTAssertEqual(LaunchAtLoginService.status(environment: fixture.environment()), .enabled)
        XCTAssertTrue(fixture.reports.isEmpty)
    }

    func testStatusRemovesFallbackWhenServiceManagementIsEnabled() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.writeLaunchAgent(executablePath: fixture.executableURL.path)

        let status = LaunchAtLoginService.status(
            environment: fixture.environment(serviceManagementStatus: { .enabled })
        )

        XCTAssertEqual(status, .enabled)
        XCTAssertFalse(fixture.plistExists)
        XCTAssertTrue(fixture.reports.isEmpty)
    }

    func testStatusIgnoresFallbackLaunchAgentWithStaleExecutablePath() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.writeLaunchAgent(executablePath: "/Applications/OldTypeSwitch.app/Contents/MacOS/TypeSwitch")

        XCTAssertEqual(LaunchAtLoginService.status(environment: fixture.environment()), .disabled)
        XCTAssertTrue(fixture.plistExists)
        XCTAssertTrue(fixture.reports.isEmpty)
    }

    func testMissingFallbackPreservesServiceManagementStatusWithoutErrors() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let cases: [(SMAppService.Status, LaunchAtLoginStatus)] = [
            (.enabled, .enabled),
            (.notRegistered, .disabled),
            (.requiresApproval, .requiresApproval),
            (.notFound, .unavailable),
        ]

        for (serviceStatus, expectedStatus) in cases {
            XCTAssertEqual(
                LaunchAtLoginService.status(
                    environment: fixture.environment(serviceManagementStatus: { serviceStatus })
                ),
                expectedStatus
            )
        }

        XCTAssertFalse(fixture.plistExists)
        XCTAssertTrue(fixture.reports.isEmpty)
    }

    func testFallbackCanBeEnabledRepeatedlyWhileServiceManagementRequiresApproval() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let environment = fixture.environment(serviceManagementStatus: { .requiresApproval })

        XCTAssertEqual(LaunchAtLoginService.setLaunchAtLogin(true, environment: environment), .enabled)
        let firstPlist = try Data(contentsOf: fixture.plistURL)
        XCTAssertEqual(LaunchAtLoginService.setLaunchAtLogin(true, environment: environment), .enabled)

        let plist = try fixture.propertyList()
        XCTAssertEqual(plist["Label"] as? String, "top.ygsgdbd.TypeSwitch")
        XCTAssertEqual(plist["ProgramArguments"] as? [String], [fixture.executableURL.path])
        XCTAssertEqual(plist["RunAtLoad"] as? Bool, true)
        XCTAssertNil(plist["KeepAlive"])
        XCTAssertEqual(try Data(contentsOf: fixture.plistURL), firstPlist)
        XCTAssertTrue(fixture.reports.isEmpty)
    }

    func testEnablingFallbackUpdatesStaleExecutablePath() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.writeLaunchAgent(executablePath: "/Applications/OldTypeSwitch.app/Contents/MacOS/TypeSwitch")

        let status = LaunchAtLoginService.setLaunchAtLogin(true, environment: fixture.environment())

        XCTAssertEqual(status, .enabled)
        XCTAssertEqual(try fixture.propertyList()["ProgramArguments"] as? [String], [fixture.executableURL.path])
        XCTAssertTrue(fixture.reports.isEmpty)
    }

    func testEnablingAlreadyRegisteredServiceManagementRemovesFallbackWithoutRegisteringAgain() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.writeLaunchAgent(executablePath: fixture.executableURL.path)

        let status = LaunchAtLoginService.setLaunchAtLogin(
            true,
            environment: fixture.environment(
                serviceManagementStatus: { .enabled },
                registerMainApp: {
                    XCTFail("Already-enabled ServiceManagement should not register again")
                }
            )
        )

        XCTAssertEqual(status, .enabled)
        XCTAssertFalse(fixture.plistExists)
        XCTAssertTrue(fixture.reports.isEmpty)
    }

    func testSuccessfulServiceManagementRegistrationMigratesExistingFallback() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.writeLaunchAgent(executablePath: fixture.executableURL.path)
        var serviceStatus = SMAppService.Status.notRegistered
        var registrationCount = 0

        let status = LaunchAtLoginService.setLaunchAtLogin(
            true,
            environment: fixture.environment(
                serviceManagementStatus: { serviceStatus },
                registerMainApp: {
                    registrationCount += 1
                    serviceStatus = .enabled
                }
            )
        )

        XCTAssertEqual(status, .enabled)
        XCTAssertEqual(registrationCount, 1)
        XCTAssertFalse(fixture.plistExists)
        XCTAssertTrue(fixture.reports.isEmpty)
    }

    func testRegistrationFailureStillEnablesFallback() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let registrationError = NSError(domain: "TypeSwitchTests.Registration", code: 42)

        let status = LaunchAtLoginService.setLaunchAtLogin(
            true,
            environment: fixture.environment(registerMainApp: { throw registrationError })
        )

        XCTAssertEqual(status, .enabled)
        XCTAssertEqual(try fixture.propertyList()["ProgramArguments"] as? [String], [fixture.executableURL.path])
        XCTAssertTrue(fixture.reports.isEmpty)
    }

    func testDisablingFallbackAndRepeatingWithMissingFileIsIdempotent() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.writeLaunchAgent(executablePath: fixture.executableURL.path)
        var unregisterCount = 0
        let environment = fixture.environment(unregisterMainApp: { unregisterCount += 1 })

        XCTAssertEqual(LaunchAtLoginService.setLaunchAtLogin(false, environment: environment), .disabled)
        XCTAssertEqual(LaunchAtLoginService.setLaunchAtLogin(false, environment: environment), .disabled)

        XCTAssertEqual(unregisterCount, 2)
        XCTAssertFalse(fixture.plistExists)
        XCTAssertTrue(fixture.reports.isEmpty)
    }

    func testUnregisterFailurePreservesEnabledServiceManagementStatusAndRemovesFallback() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.writeLaunchAgent(executablePath: fixture.executableURL.path)
        let unregisterError = NSError(domain: "TypeSwitchTests.Unregister", code: 43)

        let status = LaunchAtLoginService.setLaunchAtLogin(
            false,
            environment: fixture.environment(
                serviceManagementStatus: { .enabled },
                unregisterMainApp: { throw unregisterError }
            )
        )

        XCTAssertEqual(status, .enabled)
        XCTAssertFalse(fixture.plistExists)
        XCTAssertTrue(fixture.reports.isEmpty)
    }

    func testMalformedOrIncompleteFallbackIsReportedInsteadOfEnabled() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let invalidPropertyLists: [Any] = [
            ["unexpected array"],
            ["Label": "top.ygsgdbd.TypeSwitch"],
            ["ProgramArguments": "unexpected string"],
            ["ProgramArguments": [String]()],
        ]
        let invalidContents = try [Data("not a property list".utf8)] + invalidPropertyLists.map {
            try PropertyListSerialization.data(fromPropertyList: $0, format: .xml, options: 0)
        }

        for data in invalidContents {
            fixture.errorRecorder.reports.removeAll()
            try data.write(to: fixture.plistURL)

            XCTAssertEqual(LaunchAtLoginService.status(environment: fixture.environment()), .disabled)
            fixture.assertReported(NSError(domain: NSCocoaErrorDomain, code: NSPropertyListReadCorruptError))
            XCTAssertEqual(try Data(contentsOf: fixture.plistURL), data)
        }
    }

    func testUnreadableFallbackPathIsReportedWithoutRemovingIt() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try FileManager.default.createDirectory(at: fixture.plistURL, withIntermediateDirectories: false)

        XCTAssertEqual(LaunchAtLoginService.status(environment: fixture.environment()), .disabled)
        XCTAssertTrue(fixture.plistExists)
        XCTAssertFalse(fixture.reports.isEmpty)
        XCTAssertTrue(fixture.reports.allSatisfy { $0.url == fixture.plistURL && !$0.operation.isEmpty })
    }

    func testFallbackDirectoryCreationFailureIsReportedWithoutEnablingFallback() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let fileManager = FailingFileManager()
        let directoryError = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
        fileManager.createDirectoryError = directoryError

        let status = LaunchAtLoginService.setLaunchAtLogin(
            true,
            environment: fixture.environment(fileManager: fileManager)
        )

        XCTAssertEqual(status, .disabled)
        XCTAssertFalse(fixture.plistExists)
        fixture.assertReported(directoryError)
    }

    func testFallbackWriteFailureDoesNotReportEnabledOrRemoveBlockingDirectory() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try FileManager.default.createDirectory(at: fixture.plistURL, withIntermediateDirectories: false)

        let status = LaunchAtLoginService.setLaunchAtLogin(true, environment: fixture.environment())

        XCTAssertEqual(status, .disabled)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.plistURL.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertFalse(fixture.reports.isEmpty)
        XCTAssertTrue(fixture.reports.allSatisfy { $0.url == fixture.plistURL && !$0.operation.isEmpty })
    }

    func testFallbackRemovalFailurePreservesFileAndEnabledStatus() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.writeLaunchAgent(executablePath: fixture.executableURL.path)
        let originalData = try Data(contentsOf: fixture.plistURL)
        let fileManager = FailingFileManager()
        let removalError = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
        fileManager.removeItemError = removalError

        let status = LaunchAtLoginService.setLaunchAtLogin(
            false,
            environment: fixture.environment(fileManager: fileManager)
        )

        XCTAssertEqual(status, .enabled)
        XCTAssertEqual(try Data(contentsOf: fixture.plistURL), originalData)
        fixture.assertReported(removalError)
    }

    func testReadMissingErrorDuringRemovalIsNotSilencedAsAnAbsentFile() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let fileManager = FailingFileManager()
        let removalError = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)
        fileManager.removeItemError = removalError

        let status = LaunchAtLoginService.setLaunchAtLogin(
            false,
            environment: fixture.environment(fileManager: fileManager)
        )

        XCTAssertEqual(status, .disabled)
        fixture.assertReported(removalError)
    }
}

private struct Fixture {
    let directoryURL: URL
    let plistURL: URL
    let executableURL = URL(fileURLWithPath: "/Applications/TypeSwitch.app/Contents/MacOS/TypeSwitch")
    let errorRecorder = ErrorRecorder()

    var reports: [ReportedError] { errorRecorder.reports }
    var plistExists: Bool { FileManager.default.fileExists(atPath: plistURL.path) }

    init() throws {
        directoryURL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("TypeSwitchTests-\(UUID().uuidString)", isDirectory: true)
        plistURL = directoryURL.appendingPathComponent("top.ygsgdbd.TypeSwitch.plist")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func environment(
        serviceManagementStatus: @escaping () -> SMAppService.Status = { .notRegistered },
        registerMainApp: @escaping () throws -> Void = {},
        unregisterMainApp: @escaping () throws -> Void = {},
        fileManager: FileManager = .default
    ) -> LaunchAtLoginServiceEnvironment {
        LaunchAtLoginServiceEnvironment(
            serviceManagementStatus: serviceManagementStatus,
            registerMainApp: registerMainApp,
            unregisterMainApp: unregisterMainApp,
            plistURL: plistURL,
            executableURL: { executableURL },
            fileManager: fileManager,
            reportError: { operation, url, error in
                errorRecorder.reports.append(ReportedError(operation: operation, url: url, error: error as NSError))
            }
        )
    }

    func writeLaunchAgent(executablePath: String) throws {
        let plist: [String: Any] = [
            "Label": "top.ygsgdbd.TypeSwitch",
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL)
    }

    func propertyList() throws -> [String: Any] {
        let data = try Data(contentsOf: plistURL)
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        )
    }

    func assertReported(_ error: NSError, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(reports.map(\.error.domain), [error.domain], file: file, line: line)
        XCTAssertEqual(reports.map(\.error.code), [error.code], file: file, line: line)
        XCTAssertEqual(reports.map(\.url), [plistURL], file: file, line: line)
        XCTAssertTrue(reports.allSatisfy { !$0.operation.isEmpty }, file: file, line: line)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}

private struct ReportedError {
    let operation: String
    let url: URL
    let error: NSError
}

private final class ErrorRecorder {
    var reports: [ReportedError] = []
}

private final class FailingFileManager: FileManager, @unchecked Sendable {
    var createDirectoryError: Error?
    var removeItemError: Error?

    override func createDirectory(
        at url: URL,
        withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]? = nil
    ) throws {
        if let createDirectoryError { throw createDirectoryError }
        try super.createDirectory(at: url, withIntermediateDirectories: createIntermediates, attributes: attributes)
    }

    override func removeItem(at url: URL) throws {
        if let removeItemError { throw removeItemError }
        try super.removeItem(at: url)
    }
}
