import Foundation
import AppKit
import Combine
@preconcurrency import Combine

import Carbon
import SwiftUI

/// 输入法策略枚举
enum InputMethodStrategy: Codable {
    case fixed(String)  // 固定选择某个输入法ID
    case lastUsed       // 使用上次切换的输入法
}

/// 应用输入法设置结构体
struct AppInputMethodSettings: Codable {
    let strategy: InputMethodStrategy
    let lastUsedInputMethodId: String?  // 当strategy是lastUsed时使用
    
    init(strategy: InputMethodStrategy, lastUsedInputMethodId: String? = nil) {
        self.strategy = strategy
        self.lastUsedInputMethodId = lastUsedInputMethodId
    }
}

@MainActor
final class InputMethodManager: ObservableObject {
    static let shared = InputMethodManager()
    
    @Published var inputMethods: [InputMethod] = []
    @Published var installedApps: [AppInfo] = []
    
    // 使用原生 UserDefaults 存储应用输入法设置
    private let userDefaults = UserDefaults.standard
    private let appSettingsKey = "app-input-method-settings-v1"
    private let legacyAppSettingsKey = "appInputMethodSettings"
    
    // UI 状态
    @Published private(set) var isRefreshing: Bool = false
    @Published var isHighlighted = false
    
    var filteredApps: [AppInfo] {
        return installedApps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    
    // 存储订阅
    private var cancellables: Set<AnyCancellable> = []
    
    private init() {
        migrateLegacySettings()
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
    
    /// 设置应用的输入法（使用固定策略）
    func setInputMethod(for app: AppInfo, to inputMethodId: String?) async {
        if let inputMethodId = inputMethodId {
            let settings = AppInputMethodSettings(strategy: .fixed(inputMethodId))
            saveAppSettings(for: app.bundleId, settings: settings)
        } else {
            // 删除设置，使用默认输入法
            removeAppSettings(for: app.bundleId)
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
    
    /// 获取应用的输入法ID（兼容性方法）
    func getInputMethod(for app: AppInfo) -> String? {
        guard let settings = getAppSettings(for: app.bundleId) else { return nil }
        
        switch settings.strategy {
        case .fixed(let inputMethodId):
            return inputMethodId
        case .lastUsed:
            return settings.lastUsedInputMethodId
        }
    }
    
    /// 设置应用使用上次使用的输入法策略
    func setLastUsedInputMethodStrategy(for app: AppInfo) async {
        let settings = AppInputMethodSettings(strategy: .lastUsed, lastUsedInputMethodId: nil)
        saveAppSettings(for: app.bundleId, settings: settings)
    }
    
    /// 更新应用的上次使用输入法ID
    func updateLastUsedInputMethod(for bundleId: String, inputMethodId: String) {
        guard let settings = getAppSettings(for: bundleId),
              case .lastUsed = settings.strategy else { return }
        
        let updatedSettings = AppInputMethodSettings(strategy: .lastUsed, lastUsedInputMethodId: inputMethodId)
        saveAppSettings(for: bundleId, settings: updatedSettings)
    }
    
    /// 获取应用的输入法策略
    func getInputMethodStrategy(for app: AppInfo) -> InputMethodStrategy? {
        return getAppSettings(for: app.bundleId)?.strategy
    }
    
    
    /// 获取应用的完整输入法设置
    func getAppInputMethodSettings(for app: AppInfo) -> AppInputMethodSettings? {
        return getAppSettings(for: app.bundleId)
    }
    // MARK: - Private Methods
    
    /// 迁移旧版本设置
    private func migrateLegacySettings() {
        guard let legacySettings = userDefaults.object(forKey: legacyAppSettingsKey) as? [String: String],
              !legacySettings.isEmpty else { return }
        
        var newSettings: [String: Data] = [:]
        
        for (bundleId, inputMethodId) in legacySettings {
            if !inputMethodId.isEmpty {
                let settings = AppInputMethodSettings(strategy: .fixed(inputMethodId))
                if let data = try? JSONEncoder().encode(settings) {
                    newSettings[bundleId] = data
                }
            }
        }
        
        if !newSettings.isEmpty {
            userDefaults.set(newSettings, forKey: appSettingsKey)
            userDefaults.removeObject(forKey: legacyAppSettingsKey)
            print("Migrated \(newSettings.count) app settings to new format")
        }
    }
    
    /// 获取应用输入法设置
    private func getAppSettings(for bundleId: String) -> AppInputMethodSettings? {
        guard let settingsData = userDefaults.object(forKey: appSettingsKey) as? [String: Data],
              let data = settingsData[bundleId],
              let settings = try? JSONDecoder().decode(AppInputMethodSettings.self, from: data) else {
            return nil
        }
        return settings
    }
    
    /// 保存应用输入法设置
    private func saveAppSettings(for bundleId: String, settings: AppInputMethodSettings) {
        var settingsData = userDefaults.object(forKey: appSettingsKey) as? [String: Data] ?? [:]
        
        if let data = try? JSONEncoder().encode(settings) {
            settingsData[bundleId] = data
            userDefaults.set(settingsData, forKey: appSettingsKey)
        }
    }
    
    /// 删除应用输入法设置
    private func removeAppSettings(for bundleId: String) {
        var settingsData = userDefaults.object(forKey: appSettingsKey) as? [String: Data] ?? [:]
        settingsData.removeValue(forKey: bundleId)
        userDefaults.set(settingsData, forKey: appSettingsKey)
    }
    
    private func handleApplicationActivation(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleId = app.bundleIdentifier else { return }
        
        // 查找对应的应用信息
        guard let appInfo = installedApps.first(where: { $0.bundleId == bundleId }),
              let settings = getAppSettings(for: appInfo.bundleId) else { return }
        
        var inputMethodId: String?
        
        switch settings.strategy {
        case .fixed(let id):
            inputMethodId = id
        case .lastUsed:
            inputMethodId = settings.lastUsedInputMethodId
        }
        
        if let inputMethodId = inputMethodId, !inputMethodId.isEmpty {
            Task {
                do {
                    try InputMethodUtils.switchToInputMethod(inputMethodId)
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
