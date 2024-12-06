import Foundation
import ServiceManagement
import AppKit
import Combine
import Defaults
import Carbon
import SwiftUI

@MainActor
final class InputMethodManager: ObservableObject {
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
    @Published var searchText = ""
    @Published private(set) var isRefreshing: Bool = false
    
    // 计算属性
    var filteredApps: [AppInfo] {
        if searchText.isEmpty {
            return installedApps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        return SearchResult<AppInfo>.search(installedApps, query: searchText, by: \.name)
    }
    
    // 存储订阅
    private var cancellables: Set<AnyCancellable> = []
    private var isUpdatingAutoLaunch = false
    
    private init() {
        // 从 Defaults 加载设置
        appSettings = Defaults[.appInputMethodSettings]
        setupSubscriptions()
        
        // 初始化自启动状态
        updateAutoLaunchState()
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
    
    private func updateAutoLaunchState() {
        guard !isUpdatingAutoLaunch else { return }
        isUpdatingAutoLaunch = true
        defer { isUpdatingAutoLaunch = false }
        
        isAutoLaunchEnabled = SMAppService.mainApp.status == .enabled
    }
    
    // MARK: - Application Handling
    
    private func handleApplicationSwitch(_ notification: Notification) async {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleId = app.bundleIdentifier,
              let inputMethodId = appSettings[bundleId]
        else { return }
        
        do {
            try InputMethodUtils.switchToInputMethod(inputMethodId)
        } catch {
            print("Failed to switch input method for \(bundleId): \(error.localizedDescription)")
        }
    }
    
    // MARK: - Input Method Management
    
    func refreshInputMethods() async {
        do {
            let newInputMethods = try InputMethodUtils.fetchInputMethods()
            let newInputMethodIds = Set(newInputMethods.map(\.id))
            let oldInputMethodIds = Set(inputMethods.map(\.id))
            
            if oldInputMethodIds != newInputMethodIds {
                cleanInvalidSettings(validInputMethodIds: newInputMethodIds)
            }
            
            inputMethods = newInputMethods
        } catch {
            print("Failed to refresh input methods: \(error.localizedDescription)")
        }
    }
    
    private func cleanInvalidSettings(validInputMethodIds: Set<String>) {
        let updatedSettings = appSettings.filter { validInputMethodIds.contains($0.value) }
        if updatedSettings != appSettings {
            appSettings = updatedSettings
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
        
        isAutoLaunchEnabled = SMAppService.mainApp.status == .enabled
    }
} 
