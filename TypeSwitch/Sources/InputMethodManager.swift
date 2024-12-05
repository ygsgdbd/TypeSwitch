import Foundation
import ServiceManagement
import AppKit
import Combine
import Defaults
import Carbon

@MainActor
class InputMethodManager: ObservableObject {
    static let shared = InputMethodManager()
    
    @Published var inputMethods: [InputMethod] = []
    @Published var installedApps: [AppInfo] = []
    @Published var appSettings: [String: String] = [:] {
        didSet {
            // 当设置更新时，同步到 Defaults
            Defaults[.appInputMethodSettings] = appSettings
        }
    }
    
    // UI 状态
    @Published var isAutoLaunchEnabled = false
    @Published var isRefreshing = false
    @Published var searchText = ""
    
    var filteredApps: [AppInfo] {
        if searchText.isEmpty {
            return installedApps
        }
        return installedApps.filter { app in
            app.name.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    private var inputSourceObserver: NSObjectProtocol?
    private var workspaceObserver: NSObjectProtocol?
    
    private init() {
        // 从 Defaults 加载设置
        appSettings = Defaults[.appInputMethodSettings]
        
        // 监听输入法变化
        inputSourceObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                await self.refreshInputMethods()
            }
        }
        
        // 监听应用切换
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleId = app.bundleIdentifier
            else { return }
            
            // 检查是否有为该应用设置输入法
            if let inputMethodId = self.appSettings[bundleId] {
                Task {
                    do {
                        try await self.switchToInputMethod(inputMethodId)
                    } catch {
                        print("Failed to switch input method: \(error)")
                    }
                }
            }
        }
    }
    
    deinit {
        if let observer = inputSourceObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
    
    func refreshInputMethods() async {
        do {
            let newInputMethods = try InputMethodUtils.fetchInputMethods()
            
            // 检查输入法列表是否发生变化
            let oldInputMethodIds = Set(inputMethods.map { $0.id })
            let newInputMethodIds = Set(newInputMethods.map { $0.id })
            
            // 如果输入法列表发生变化，清理无效的设置
            if oldInputMethodIds != newInputMethodIds {
                cleanInvalidSettings(validInputMethodIds: newInputMethodIds)
            }
            
            inputMethods = newInputMethods
        } catch {
            print("Failed to refresh input methods: \(error)")
        }
    }
    
    private func cleanInvalidSettings(validInputMethodIds: Set<String>) {
        var updatedSettings = appSettings
        var hasChanges = false
        
        // 移除不存在的输入法设置
        for (bundleId, inputMethodId) in appSettings {
            if !validInputMethodIds.contains(inputMethodId) {
                updatedSettings[bundleId] = nil
                hasChanges = true
            }
        }
        
        if hasChanges {
            appSettings = updatedSettings
        }
    }
    
    func switchToInputMethod(_ inputMethodID: String) async throws {
        try await Task.detached {
            try InputMethodUtils.switchToInputMethod(inputMethodID)
        }.value
    }
    
    func refreshInstalledApps() async {
        installedApps = await AppListUtils.fetchInstalledApps()
    }
    
    // 刷新所有数据
    func refreshAllData() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        
        await refreshInputMethods()
        await refreshInstalledApps()
        isAutoLaunchEnabled = SMAppService.mainApp.status == .enabled
    }
}
