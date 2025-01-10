import Foundation
import ServiceManagement
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
    @Published var isQuickSwitchEnabled: Bool {
        didSet {
            Defaults[.quickSwitchEnabled] = isQuickSwitchEnabled
        }
    }
    
    // 计算属性
    var isAutoLaunchEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
    
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
        isQuickSwitchEnabled = Defaults[.quickSwitchEnabled]
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
    
    // MARK: - Auto Launch
    
    /// 检查自启动状态并同步 UI
    func checkAutoLaunchStatus() async {
        let currentStatus = SMAppService.mainApp.status
        logger.info("Current auto launch status: \(currentStatus.rawValue)")
        objectWillChange.send()
    }
    
    func setAutoLaunch(enabled: Bool) async throws {
        logger.info("Setting auto launch to: \(enabled), current status: \(SMAppService.mainApp.status.rawValue)")
        
        // 检查当前状态
        let currentStatus = SMAppService.mainApp.status
        
        // 如果当前状态已经是目标状态，直接返回
        if (enabled && currentStatus == .enabled) || (!enabled && currentStatus == .notRegistered) {
            logger.info("Auto launch is already in desired state")
            return
        }
        
        // 执行注册或注销操作
        if enabled {
            try SMAppService.mainApp.register()
            
            // 检查注册结果
            let newStatus = SMAppService.mainApp.status
            switch newStatus {
            case .enabled:
                logger.info("Auto launch enabled successfully")
            case .requiresApproval:
                logger.info("Auto launch requires system approval")
                throw NSError(domain: "TypeSwitch", code: 1, 
                    userInfo: [NSLocalizedDescriptionKey: "需要在系统设置的登录项中批准 TypeSwitch"])
            case .notRegistered:
                logger.error("Failed to enable auto launch: status is notRegistered")
                throw NSError(domain: "TypeSwitch", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "无法启用自动启动，请稍后重试"])
            case .notFound:
                logger.error("Failed to enable auto launch: status is notFound")
                throw NSError(domain: "TypeSwitch", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "无法启用自动启动，请稍后重试"])
            @unknown default:
                logger.error("Failed to enable auto launch: unknown status \(newStatus.rawValue)")
                throw NSError(domain: "TypeSwitch", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "无法启用自动启动，请稍后重试"])
            }
        } else {
            try await SMAppService.mainApp.unregister()
            
            // 验证注销结果
            let finalStatus = SMAppService.mainApp.status
            if finalStatus != .notRegistered {
                logger.error("Failed to disable auto launch: status is \(finalStatus.rawValue)")
                throw NSError(domain: "TypeSwitch", code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "请在系统设置的登录项中手动移除 TypeSwitch"])
            }
            logger.info("Auto launch disabled successfully")
        }
        
        objectWillChange.send()
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
    
    // MARK: - Input Method Switching
    
    func switchInputMethodForCurrentApp() async -> (success: Bool, inputMethodName: String?) {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleId = app.bundleIdentifier else { return (false, nil) }
        
        print("当前应用: \(app.localizedName ?? "unknown") (\(bundleId))")
        
        // 构建可选择的输入法列表：[默认, ...已安装的输入法]
        var availableInputMethods = [""] // 空字符串代表默认输入法
        availableInputMethods.append(contentsOf: inputMethods.map(\.id))
        
        // 获取当前应用保存的输入法设置
        let currentSetting = appSettings[bundleId]?.flatMap { $0 } ?? ""
        print("当前设置的输入法: \(currentSetting.isEmpty ? "默认" : currentSetting)")
        
        // 找到当前设置在列表中的位置
        let currentIndex = availableInputMethods.firstIndex(where: { $0 == currentSetting }) ?? -1
        
        // 计算下一个输入法的索引
        let nextIndex = (currentIndex + 1) % availableInputMethods.count
        let nextInputMethodId = availableInputMethods[nextIndex]
        print("切换到输入法: \(nextInputMethodId.isEmpty ? "默认" : nextInputMethodId)")
        
        do {
            var switchedInputMethodName: String = "默认"
            
            if nextInputMethodId.isEmpty {
                // 切换到默认输入法
                appSettings[bundleId] = nil
                // 如果有全局默认输入法，切换到它
                if let defaultInputMethod = inputMethods.first {
                    try InputMethodUtils.switchToInputMethod(defaultInputMethod.id)
                    switchedInputMethodName = defaultInputMethod.name
                    print("已切换到默认输入法: \(defaultInputMethod.id)")
                }
                
                // 使用动画更新状态
                withAnimation(.interpolatingSpring(stiffness: 170, damping: 5)) {
                    isHighlighted = true
                }
                
                // 0.2秒后恢复
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    withAnimation(.interpolatingSpring(stiffness: 170, damping: 5)) {
                        self.isHighlighted = false
                    }
                }
                
                return (true, "默认")
            } else {
                // 切换到选定的输入法
                appSettings[bundleId] = nextInputMethodId
                try InputMethodUtils.switchToInputMethod(nextInputMethodId)
                if let inputMethod = inputMethods.first(where: { $0.id == nextInputMethodId }) {
                    switchedInputMethodName = inputMethod.name
                }
                print("已切换到输入法: \(nextInputMethodId)")
                
                // 使用动画更新状态
                withAnimation(.interpolatingSpring(stiffness: 170, damping: 5)) {
                    isHighlighted = true
                }
                
                // 0.2秒后恢复
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    withAnimation(.interpolatingSpring(stiffness: 170, damping: 5)) {
                        self.isHighlighted = false
                    }
                }
                
                return (true, switchedInputMethodName)
            }
            
            
        } catch {
            print("切换输入法失败: \(error.localizedDescription)")
            return (false, nil)
        }
    }
    
    // MARK: - Quick Switch
    
    func quickSwitch() async -> (success: Bool, inputMethodName: String?) {
        if isQuickSwitchEnabled {
            return await switchInputMethodForCurrentApp()
        } else {
            return (false, nil)
        }
    }
} 
