import AppKit
import Carbon
import Combine
import Foundation
import SwiftUI
import Defaults



@MainActor
final class InputMethodManager: ObservableObject {
    static let shared = InputMethodManager()
    
    @Published var inputMethods: [InputMethod] = []
    @Published var installedApps: [AppInfo] = []
    @Published var runningApps: [AppInfo] = []
    
    // UI 状态
    @Published private(set) var settingsVersion: Int = 0  // 跟踪设置变化以触发 UI 更新
    
    
    // 存储订阅
    private var cancellables: Set<AnyCancellable> = []
    
    private init() {
        Task { await refreshAllData() }
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
        
        // 监听应用启动通知
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
        
        // 监听应用退出通知
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
        
        // 监听应用激活通知
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] notification in
                Task { @MainActor in
                    await self?.handleAppActivation(notification)
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    
    func refreshAllData() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.refreshInputMethods() }
            group.addTask { await self.refreshInstalledApps() }
            group.addTask { await self.refreshRunningApps() }
        }
    }
    
    func refreshInputMethods() async {
        do {
            let methods = try InputMethodUtils.fetchInputMethods()
            self.inputMethods = methods
        } catch {
            print("Failed to fetch input methods: \(error)")
        }
    }
    
    /// 刷新已安装的应用
    func refreshInstalledApps() async {
        installedApps = await AppListUtils.fetchInstalledApps()
    }
    
    /// 刷新运行中的应用
    func refreshRunningApps() async {
        runningApps = await AppListUtils.fetchRunningApps()
    }
    
    // MARK: - Private Methods
    
    
    /// 处理应用激活事件
    private func handleAppActivation(_ notification: Notification) async {
        guard let userInfo = notification.userInfo,
              let app = userInfo[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleId = app.bundleIdentifier else {
            return
        }
        
        // 查找对应的应用信息
        guard let appInfo = installedApps.first(where: { $0.bundleId == bundleId }) else {
            return
        }
        
        // 检查是否有为该应用设置的输入法
        guard let targetInputMethodId = getInputMethod(for: appInfo) else {
            return
        }
        
        // 检查当前输入法是否已经是目标输入法
        do {
            let currentInputMethodId = try InputMethodUtils.getCurrentInputMethodId()
            if currentInputMethodId == targetInputMethodId {
                return // 已经是目标输入法，无需切换
            }
        } catch {
            print("获取当前输入法失败: \(error)")
            return
        }
        
        // 执行输入法切换
        do {
            try InputMethodUtils.switchToInputMethod(targetInputMethodId)
            print("已为应用 \(appInfo.name) 切换到输入法: \(targetInputMethodId)")
        } catch {
            print("切换输入法失败: \(error)")
        }
    }
    
    /// 设置应用的输入法
    func setInputMethod(for app: AppInfo, to inputMethodId: String?) {
        var settings = Defaults[.appInputMethodSettings]
        
        if let inputMethodId = inputMethodId {
            // 设置输入法
            settings[app.bundleId] = inputMethodId
        } else {
            // 移除输入法设置
            settings.removeValue(forKey: app.bundleId)
        }
        
        Defaults[.appInputMethodSettings] = settings
        settingsVersion += 1
    }
    
    /// 获取应用的输入法ID
    func getInputMethod(for app: AppInfo) -> String? {
        return Defaults[.appInputMethodSettings][app.bundleId] ?? nil
    }
    
    // MARK: - UI Helper Methods
    
    /// 获取已配置输入法的应用列表
    var configuredApps: [AppInfo] {
        let settings = Defaults[.appInputMethodSettings]
        return installedApps.filter { app in
            settings[app.bundleId] != nil
        }
    }
    
    /// 获取应用选中的输入法名称
    func getSelectedInputMethodName(for app: AppInfo) -> String? {
        // 依赖于 settingsVersion 以确保设置变化时 UI 更新
        _ = settingsVersion
        
        guard let inputMethodId = getInputMethod(for: app), !inputMethodId.isEmpty else {
            return nil
        }
        
        return inputMethods.first(where: { $0.id == inputMethodId })?.name
    }
}
