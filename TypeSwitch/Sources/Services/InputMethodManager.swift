import Foundation
import Sharing
import AppKit
import Combine
@preconcurrency import Combine

import Carbon
import SwiftUI

@MainActor
final class InputMethodManager: ObservableObject {
    static let shared = InputMethodManager()
    
    @Published var inputMethods: [InputMethod] = []
    @Published var installedApps: [AppInfo] = []
    @Shared(.appStorage("appInputMethodSettings")) var appSettings: [String: String?] = [:]
    
    // UI 状态
    @Published var searchText = ""
    @Published private(set) var isRefreshing: Bool = false
    @Published var isHighlighted = false
    
    var filteredApps: [AppInfo] {
        if searchText.isEmpty {
            return installedApps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        return SearchResult<AppInfo>.search(installedApps, query: searchText, by: \.name)
    }
    
    // 存储订阅
    private var cancellables: Set<AnyCancellable> = []
    
    private init() {
        // appSettings 现在通过 @Shared 自动管理
        setupSubscriptions()
    }
    
    deinit {
        // cancellables 会在对象销毁时自动清理
    }
    
    // MARK: - Setup
    
    private func setupSubscriptions() {
        // 监听输入法变化
        DistributedNotificationCenter.default()
            .publisher(for: NSNotification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String))
            .receive(on: DispatchQueue.main)
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.refreshInputMethods()
                }
            }
            .store(in: &cancellables)
        
        // 监听应用激活
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleApplicationActivation(notification)
            }
            .store(in: &cancellables)
        
        // 监听应用启动
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .receive(on: DispatchQueue.main)
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.refreshRunningApps()
                }
            }
            .store(in: &cancellables)
        
        // 监听应用退出
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didTerminateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.refreshRunningApps()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    
    func refreshAllData() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.refreshInputMethods() }
            group.addTask { await self.refreshRunningApps() }
        }
    }
    
    func refreshInputMethods() async {
        do {
            let methods = try InputMethodUtils.fetchInputMethods()
            await MainActor.run {
                self.inputMethods = methods
            }
        } catch {
            print("Failed to fetch input methods: \(error)")
        }
    }
    
    /// 刷新运行中的应用（替代原来的扫描所有应用目录的方式）
    func refreshRunningApps() async {
        let apps = await AppListUtils.fetchRunningApps()
        await MainActor.run {
            self.installedApps = apps
        }
    }
    
    /// 保留原方法以兼容性，但内部调用新的运行中应用获取方法
    func refreshInstalledApps() async {
        await refreshRunningApps()
    }
    
    func setInputMethod(for app: AppInfo, to inputMethodId: String?) async {
        $appSettings.withLock { settings in
            settings[app.bundleId] = inputMethodId
        }
        
        // 如果当前应用是目标应用，立即切换输入法
        if let currentApp = NSWorkspace.shared.frontmostApplication,
           currentApp.bundleIdentifier == app.bundleId {
            if let inputMethodId = inputMethodId {
                do {
                    try InputMethodUtils.switchToInputMethod(inputMethodId)
                } catch {
                    print("Failed to switch input method: \(error)")
                }
            }
        }
    }
    
    func getInputMethod(for app: AppInfo) -> String? {
        return appSettings[app.bundleId] ?? nil
    }
    
    // MARK: - Private Methods
    
    private func handleApplicationActivation(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleId = app.bundleIdentifier else { return }
        
        // 查找对应的应用信息
        guard let appInfo = installedApps.first(where: { $0.bundleId == bundleId }) else { return }
        
        // 获取为该应用设置的输入法
        if let inputMethodId = appSettings[appInfo.bundleId], let idToSwitch = inputMethodId {
            Task {
                do {
                    try InputMethodUtils.switchToInputMethod(idToSwitch)
                } catch {
                    print("Failed to switch input method: \(error)")
                }
            }
        }
    }
    
    // MARK: - Computed Properties
    
    var availableInputMethods: [InputMethod] {
        return inputMethods
    }
}
