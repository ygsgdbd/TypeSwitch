import Foundation
import Carbon
import AppKit
import OSLog

private let logger = Logger(subsystem: "top.ygsgdbd.TypeSwitch", category: "GlobalShortcutManager")

@MainActor
final class GlobalShortcutManager {
    static let shared = GlobalShortcutManager()
    
    private var eventHandler: EventHandlerRef?
    
    private init() {}
    
    deinit {
        Task { @MainActor in
            await unregisterShortcut()
        }
    }
    
    func registerShortcut() {
        // 创建快捷键组合：Control + Shift + Space
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType("TSWT".utf16.reduce(0, { ($0 << 8) + UInt32($1) }))
        hotKeyID.id = 1
        
        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = OSType(kEventHotKeyPressed)
        
        // 注册事件处理器
        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, eventRef, userData) -> OSStatus in
                guard let eventRef = eventRef else { return OSStatus(eventNotHandledErr) }
                guard let userData = userData else { return OSStatus(eventNotHandledErr) }
                
                let manager = Unmanaged<GlobalShortcutManager>.fromOpaque(userData).takeUnretainedValue()
                return manager.handleHotKeyEvent(eventRef)
            },
            1,
            &eventType,
            selfPtr,
            &eventHandler
        )
        
        if status != noErr {
            logger.error("Failed to install event handler: \(status)")
            return
        }
        
        // 注册快捷键
        var hotKeyRef: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_Space),  // 空格键
            UInt32(controlKey | shiftKey),  // Control + Shift 组合键
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        if registerStatus != noErr {
            logger.error("Failed to register hot key: \(registerStatus)")
            return
        }
        
        logger.info("Successfully registered global shortcut")
    }
    
    private func unregisterShortcut() async {
        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
            logger.info("Unregistered global shortcut")
        }
    }
    
    private func handleHotKeyEvent(_ eventRef: EventRef) -> OSStatus {
        // 获取当前激活的应用
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != nil else {
            return OSStatus(eventNotHandledErr)
        }
        
        // 切换到下一个输入法
        Task { @MainActor in
            do {
                let inputMethods = try InputMethodUtils.fetchInputMethods()
                
                // 获取当前输入法
                let currentSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
                guard let currentSource = currentSource,
                      let currentSourceID = TISGetInputSourceProperty(currentSource, kTISPropertyInputSourceID)
                        .map({ Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String })
                else {
                    return
                }
                
                // 找到当前输入法的索引
                guard let currentIndex = inputMethods.firstIndex(where: { $0.id == currentSourceID }) else {
                    return
                }
                
                // 计算下一个输入法的索引
                let nextIndex = (currentIndex + 1) % inputMethods.count
                let nextInputMethod = inputMethods[nextIndex]
                
                // 切换到下一个输入法
                try InputMethodUtils.switchToInputMethod(nextInputMethod.id)
                logger.info("Switched to input method: \(nextInputMethod.name)")
                
                // 显示输入法切换提示窗口
                DispatchQueue.main.async {
                    InputMethodSelectorWindow.shared.showWithInputMethod(nextInputMethod)
                }
            } catch {
                logger.error("Failed to switch input method: \(error.localizedDescription)")
            }
        }
        
        return noErr
    }
} 