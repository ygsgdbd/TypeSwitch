import Foundation
import AppKit
import Combine
import Defaults
import Carbon
import SwiftUI
import Logging

@MainActor
final class InputMethodManager: ObservableObject {
    static let shared = InputMethodManager()
    
    private let logger = LoggerUtils.autoLaunch
    private let securityLogger = LoggerUtils.security
    
    @Published var inputMethods: [InputMethod] = []
    @Published var installedApps: [AppInfo] = []
    @Published var appSettings: [String: String?] = [:] {
        didSet {
            // 当设置更新时，同步到 Defaults
            Defaults[.appInputMethodSettings] = appSettings
        }
    }
    
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
        // 从 Defaults 加载设置
        appSettings = Defaults[.appInputMethodSettings]
        setupSubscriptions()
    }
    
    deinit {
        cancellables.removeAll()
    }
    
    // MARK: - Setup
    
    private func setupSubscriptions() {
        // 监听输入法变化
        DistributedNotificationCenter.default()
            .publisher(for: NSNotification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String))
            .receive(on: DispatchQueue.main)
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [self] _ in
                Task { await refreshInputMethods() }
            }
            .store(in: &cancellables)
        
        // 监听应用切换
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [self] notification in
                Task { await handleApplicationSwitch(notification) }
            }
            .store(in: &cancellables)
    }
    
    
    // MARK: - Application Handling
    
    private func handleApplicationSwitch(_ notification: Notification) async {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleId = app.bundleIdentifier,
              let inputMethodId = appSettings[bundleId],
              let actualInputMethodId = inputMethodId
        else { return }
        
        do {
            try InputMethodUtils.switchToInputMethod(actualInputMethodId)
        } catch {
            logger.error("Failed to switch input method for \(bundleId): \(error.localizedDescription)")
        }
    }
    
    // MARK: - Input Method Management
    
    func refreshInputMethods() async {
        do {
            let newInputMethods = try InputMethodUtils.fetchInputMethods()
            let validInputMethodIds = Set(newInputMethods.map(\.id))
            
            // 清理无效的输入法设置
            cleanInvalidSettings(validInputMethodIds: validInputMethodIds)
            
            inputMethods = newInputMethods
        } catch {
            logger.error("Failed to refresh input methods: \(error.localizedDescription)")
        }
    }
    
    private func cleanInvalidSettings(validInputMethodIds: Set<String>) {
        // 清理不存在的输入法设置
        appSettings = appSettings.filter { pair in
            if let inputMethodId = pair.value {
                return validInputMethodIds.contains(inputMethodId)
            }
            return true // 保留值为 nil 的设置，因为这表示使用默认输入法
        }
    }
    
    // MARK: - App Management
    
    func refreshInstalledApps() async {
        installedApps = await AppListUtils.fetchInstalledApps()
    }
    
    // MARK: - Data Refresh
    
    func refreshAllData() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.refreshInputMethods() }
            group.addTask { await self.refreshInstalledApps() }
            await group.waitForAll()
        }
    }
    
    
    // MARK: - Menu Bar Support
    
    /// 获取可用的输入法列表（用于菜单显示）
    var availableInputMethods: [String] {
        return inputMethods.map(\.name)
    }
    
    /// 为指定应用设置输入法
    func setInputMethod(for app: AppInfo, to inputMethodName: String) async {
        let bundleId = app.bundleId
        
        // 根据输入法名称找到对应的 ID
        let inputMethodId = inputMethods.first { $0.name == inputMethodName }?.id
        
        // 更新设置
        appSettings[bundleId] = inputMethodId
        
        // 如果当前应用是目标应用，立即切换输入法
        if let currentApp = NSWorkspace.shared.frontmostApplication,
           currentApp.bundleIdentifier == bundleId {
            if let inputMethodId = inputMethodId {
                do {
                    try InputMethodUtils.switchToInputMethod(inputMethodId)
                } catch {
                    logger.error("Failed to switch input method: \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// 为指定应用快速切换输入法
    func quickSwitchForApp(_ app: AppInfo) async {
        let bundleId = app.bundleId
        
        // 构建可选择的输入法列表
        var availableInputMethods = [""] // 空字符串代表默认输入法
        availableInputMethods.append(contentsOf: inputMethods.map(\.id))
        
        // 获取当前应用保存的输入法设置
        let currentSetting = appSettings[bundleId]?.flatMap { $0 } ?? ""
        
        // 找到当前设置在列表中的位置
        let currentIndex = availableInputMethods.firstIndex(where: { $0 == currentSetting }) ?? -1
        
        // 计算下一个输入法的索引
        let nextIndex = (currentIndex + 1) % availableInputMethods.count
        let nextInputMethodId = availableInputMethods[nextIndex]
        
        // 更新设置
        appSettings[bundleId] = nextInputMethodId.isEmpty ? nil : nextInputMethodId
        
        // 如果当前应用是目标应用，立即切换输入法
        if let currentApp = NSWorkspace.shared.frontmostApplication,
           currentApp.bundleIdentifier == bundleId {
            if !nextInputMethodId.isEmpty {
                do {
                    try InputMethodUtils.switchToInputMethod(nextInputMethodId)
                } catch {
                    logger.error("Failed to switch input method: \(error.localizedDescription)")
                }
            }
        }
    }
} 
