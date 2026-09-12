import Foundation
@testable import TypeSwitch

actor SwitchRecorder {
    private(set) var values: [String] = []

    func record(_ inputMethodId: String) {
        values.append(inputMethodId)
    }
}

actor InputMethodRefreshGate {
    private let latestInputMethods: [InputMethod]
    private var callCount = 0
    private var firstContinuation: CheckedContinuation<
        Result<[InputMethod], InputMethodService.InputMethodError>,
        Never
    >?
    private var firstStartedContinuation: CheckedContinuation<Void, Never>?
    private var hasStartedFirstCall = false

    init(latestInputMethods: [InputMethod]) {
        self.latestInputMethods = latestInputMethods
    }

    func value() async throws -> [InputMethod] {
        callCount += 1
        guard callCount == 1 else { return latestInputMethods }

        let result = await withCheckedContinuation { continuation in
            firstContinuation = continuation
            hasStartedFirstCall = true
            firstStartedContinuation?.resume()
            firstStartedContinuation = nil
        }
        return try result.get()
    }

    func waitUntilFirstStarted() async {
        guard !hasStartedFirstCall else { return }
        await withCheckedContinuation { continuation in
            firstStartedContinuation = continuation
        }
    }

    func resumeFirst(with result: Result<[InputMethod], InputMethodService.InputMethodError>) {
        firstContinuation?.resume(returning: result)
        firstContinuation = nil
    }
}

actor InputMethodLookupGate {
    private let firstValue: String
    private let subsequentValue: String
    private var callCount = 0
    private var firstContinuation: CheckedContinuation<String, Never>?
    private var firstStartedContinuation: CheckedContinuation<Void, Never>?
    private var hasStartedFirstCall = false

    init(firstValue: String, subsequentValue: String = "") {
        self.firstValue = firstValue
        self.subsequentValue = subsequentValue
    }

    func value() async -> String {
        callCount += 1
        guard callCount == 1 else { return subsequentValue }

        return await withCheckedContinuation { continuation in
            firstContinuation = continuation
            hasStartedFirstCall = true
            firstStartedContinuation?.resume()
            firstStartedContinuation = nil
        }
    }

    func waitForFirstCall() async {
        guard !hasStartedFirstCall else { return }
        await withCheckedContinuation { continuation in
            firstStartedContinuation = continuation
        }
    }

    func resumeFirst() {
        firstContinuation?.resume(returning: firstValue)
        firstContinuation = nil
    }
}

actor InputMethodSwitchGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var hasStarted = false

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            hasStarted = true
            startedContinuation?.resume()
            startedContinuation = nil
        }
    }

    func waitUntilStarted() async {
        guard !hasStarted else { return }
        await withCheckedContinuation { continuation in
            startedContinuation = continuation
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

actor FrontmostApplicationGate {
    private let appInfo: AppInfo?
    private var continuation: CheckedContinuation<AppInfo?, Never>?
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var hasStarted = false

    init(appInfo: AppInfo?) {
        self.appInfo = appInfo
    }

    func value() async -> AppInfo? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            hasStarted = true
            startedContinuation?.resume()
            startedContinuation = nil
        }
    }

    func waitUntilStarted() async {
        guard !hasStarted else { return }
        await withCheckedContinuation { continuation in
            startedContinuation = continuation
        }
    }

    func resume() {
        continuation?.resume(returning: appInfo)
        continuation = nil
    }
}

enum TestError: Error {
    case failed
}
