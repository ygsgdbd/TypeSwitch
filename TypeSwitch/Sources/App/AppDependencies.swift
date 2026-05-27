import AppKit
import Carbon
import ComposableArchitecture
import Foundation

private struct NotificationObserverToken: @unchecked Sendable {
    let rawValue: NSObjectProtocol
}

enum LaunchAtLoginStatus: Equatable, Sendable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable

    var isToggleOn: Bool {
        switch self {
        case .enabled, .requiresApproval:
            return true
        case .disabled, .unavailable:
            return false
        }
    }
}

struct WorkspaceClient {
    enum Event: Equatable, Sendable {
        case launched(AppInfo)
        case terminated(bundleId: String)
        case activated(AppInfo)
    }

    var frontmostApplication: @Sendable () async -> AppInfo?
    var runningApplications: @Sendable () async -> [AppInfo]
    var events: @Sendable () async -> AsyncStream<Event>
}

extension WorkspaceClient: DependencyKey {
    static let liveValue = Self(
        frontmostApplication: {
            await AppListService.frontmostApplication()
        },
        runningApplications: {
            await AppListService.fetchRunningApps()
        },
        events: {
            await MainActor.run {
                AsyncStream { continuation in
                    let notificationCenter = NSWorkspace.shared.notificationCenter

                    let launchObserver = NotificationObserverToken(
                        rawValue: notificationCenter.addObserver(
                            forName: NSWorkspace.didLaunchApplicationNotification,
                            object: nil,
                            queue: nil
                        ) { notification in
                            guard let processIdentifier = (
                                notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                            )?.processIdentifier else {
                                return
                            }

                            Task { @MainActor [processIdentifier] in
                                guard
                                    let runningApplication = NSRunningApplication(processIdentifier: processIdentifier),
                                    let appInfo = AppListService.trackedRunningApplicationInfo(for: runningApplication)
                                else {
                                    return
                                }
                                continuation.yield(.launched(appInfo))
                            }
                        }
                    )

                    let terminateObserver = NotificationObserverToken(
                        rawValue: notificationCenter.addObserver(
                            forName: NSWorkspace.didTerminateApplicationNotification,
                            object: nil,
                            queue: nil
                        ) { notification in
                            guard
                                let runningApplication = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                                let bundleId = runningApplication.bundleIdentifier,
                                bundleId != Bundle.main.bundleIdentifier
                            else {
                                return
                            }
                            continuation.yield(.terminated(bundleId: bundleId))
                        }
                    )

                    let activateObserver = NotificationObserverToken(
                        rawValue: notificationCenter.addObserver(
                            forName: NSWorkspace.didActivateApplicationNotification,
                            object: nil,
                            queue: nil
                        ) { notification in
                            guard let processIdentifier = (
                                notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                            )?.processIdentifier else {
                                return
                            }

                            Task { @MainActor [processIdentifier] in
                                guard
                                    let runningApplication = NSRunningApplication(processIdentifier: processIdentifier),
                                    let appInfo = AppListService.trackedRunningApplicationInfo(for: runningApplication)
                                else {
                                    return
                                }
                                continuation.yield(.activated(appInfo))
                            }
                        }
                    )

                    continuation.onTermination = { _ in
                        Task { @MainActor in
                            notificationCenter.removeObserver(launchObserver.rawValue)
                            notificationCenter.removeObserver(terminateObserver.rawValue)
                            notificationCenter.removeObserver(activateObserver.rawValue)
                        }
                    }
                }
            }
        }
    )

    static let testValue = Self(
        frontmostApplication: { nil },
        runningApplications: { [] },
        events: { AsyncStream { _ in } }
    )
}

extension DependencyValues {
    var workspaceClient: WorkspaceClient {
        get { self[WorkspaceClient.self] }
        set { self[WorkspaceClient.self] = newValue }
    }
}

struct InputMethodClient {
    var fetchInputMethods: @Sendable () async throws -> [InputMethod]
    var currentInputMethodId: @Sendable () async throws -> String
    var switchToInputMethod: @Sendable (_ inputMethodId: String) async throws -> Void
    var availabilityChanges: @Sendable () async -> AsyncStream<Void>
    var selectionChanges: @Sendable () async -> AsyncStream<String>
}

extension InputMethodClient: DependencyKey {
    static let liveValue = Self(
        fetchInputMethods: {
            try await InputMethodService.fetchInputMethods()
        },
        currentInputMethodId: {
            try await InputMethodService.getCurrentInputMethodId()
        },
        switchToInputMethod: { inputMethodId in
            try await InputMethodService.switchToInputMethod(inputMethodId)
        },
        availabilityChanges: {
            AsyncStream { continuation in
                let notificationCenter = DistributedNotificationCenter.default()
                let observer = NotificationObserverToken(
                    rawValue: notificationCenter.addObserver(
                        forName: NSNotification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String),
                        object: nil,
                        queue: nil
                    ) { _ in
                        continuation.yield(())
                    }
                )

                continuation.onTermination = { _ in
                    notificationCenter.removeObserver(observer.rawValue)
                }
            }
        },
        selectionChanges: {
            AsyncStream { continuation in
                let notificationCenter = DistributedNotificationCenter.default()
                let observer = NotificationObserverToken(
                    rawValue: notificationCenter.addObserver(
                        forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
                        object: nil,
                        queue: nil
                    ) { _ in
                        Task { @MainActor in
                            guard let inputMethodId = try? InputMethodService.getCurrentInputMethodId() else {
                                return
                            }
                            continuation.yield(inputMethodId)
                        }
                    }
                )

                continuation.onTermination = { _ in
                    notificationCenter.removeObserver(observer.rawValue)
                }
            }
        }
    )

    static let testValue = Self(
        fetchInputMethods: { [] },
        currentInputMethodId: { "" },
        switchToInputMethod: { _ in },
        availabilityChanges: { AsyncStream { _ in } },
        selectionChanges: { AsyncStream { _ in } }
    )
}

extension DependencyValues {
    var inputMethodClient: InputMethodClient {
        get { self[InputMethodClient.self] }
        set { self[InputMethodClient.self] = newValue }
    }
}

struct LaunchAtLoginClient {
    var status: @Sendable () async -> LaunchAtLoginStatus
    var setEnabled: @Sendable (_ enabled: Bool) async -> LaunchAtLoginStatus
}

extension LaunchAtLoginClient: DependencyKey {
    static let liveValue = Self(
        status: {
            LaunchAtLoginService.status
        },
        setEnabled: { enabled in
            LaunchAtLoginService.setLaunchAtLogin(enabled)
        }
    )

    static let testValue = Self(
        status: { .disabled },
        setEnabled: { $0 ? .enabled : .disabled }
    )
}

extension DependencyValues {
    var launchAtLoginClient: LaunchAtLoginClient {
        get { self[LaunchAtLoginClient.self] }
        set { self[LaunchAtLoginClient.self] = newValue }
    }
}
