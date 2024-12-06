import Foundation
import Carbon
import OSLog

private let logger = Logger(subsystem: "top.ygsgdbd.TypeSwitch", category: "InputMethodUtils")

enum InputMethodError: LocalizedError {
    case failedToGetInputSources
    case inputMethodNotFound
    case failedToSwitchInputMethod
    case inputMethodNotEnabled
    case notOnMainThread
    
    var errorDescription: String? {
        switch self {
        case .failedToGetInputSources:
            return "获取输入法列表失败"
        case .inputMethodNotFound:
            return "找不到指定的输入法"
        case .failedToSwitchInputMethod:
            return "切换输入法失败"
        case .inputMethodNotEnabled:
            return "输入法未启用"
        case .notOnMainThread:
            return "必须在主线程调用"
        }
    }
}

enum InputMethodUtils {
    @MainActor
    static func fetchInputMethods() throws -> [InputMethod] {
        // 确保在主线程调用
        guard Thread.isMainThread else {
            logger.error("fetchInputMethods must be called on main thread")
            throw InputMethodError.notOnMainThread
        }
        
        // 创建输入源列表
        guard let inputSourceList = TISCreateInputSourceList(nil, false)?.takeRetainedValue(),
              let inputSources = (inputSourceList as NSArray) as? [TISInputSource] else {
            logger.error("Failed to create input source list")
            throw InputMethodError.failedToGetInputSources
        }
        
        // 过滤和转换输入源
        let methods = inputSources.compactMap { source -> InputMethod? in
            guard let properties = getInputSourceProperties(source),
                  isValidInputSourceType(properties.sourceType),
                  properties.isSelectable && properties.isEnabled else {
                return nil
            }
            
            return InputMethod(id: properties.sourceID, name: properties.localizedName)
        }
        
        // 按本地化名称排序
        return methods.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    
    @MainActor
    static func switchToInputMethod(_ inputMethodID: String) throws {
        // 确保在主线程调用
        guard Thread.isMainThread else {
            logger.error("switchToInputMethod must be called on main thread")
            throw InputMethodError.notOnMainThread
        }
        
        // 创建输入���列表
        guard let inputSourceList = TISCreateInputSourceList(nil, false)?.takeRetainedValue(),
              let inputSources = (inputSourceList as NSArray) as? [TISInputSource] else {
            logger.error("Failed to create input source list")
            throw InputMethodError.failedToGetInputSources
        }
        
        // 查找目标输入源
        guard let targetSource = inputSources.first(where: { source in
            guard let properties = getInputSourceProperties(source) else {
                return false
            }
            return properties.sourceID == inputMethodID
        }) else {
            logger.error("Input method not found: \(inputMethodID)")
            throw InputMethodError.inputMethodNotFound
        }
        
        // 切换输入法前确保输入法是启用的
        guard let enabledPtr = TISGetInputSourceProperty(targetSource, kTISPropertyInputSourceIsEnabled),
              let enabled = Unmanaged<CFBoolean>.fromOpaque(enabledPtr).takeUnretainedValue() as? Bool,
              enabled else {
            logger.error("Input method is not enabled: \(inputMethodID)")
            throw InputMethodError.inputMethodNotEnabled
        }
        
        let status = TISSelectInputSource(targetSource)
        if status != noErr {
            logger.error("Failed to switch input method: \(status)")
            throw InputMethodError.failedToSwitchInputMethod
        }
        logger.info("Successfully switched to input method: \(inputMethodID)")
    }
    
    // MARK: - Private Helpers
    
    @MainActor
    private static func getInputSourceProperties(_ source: TISInputSource) -> InputSourceProperties? {
        // 获取输入源ID
        guard let sourceIDPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID),
              let sourceID = Unmanaged<CFString>.fromOpaque(sourceIDPtr).takeUnretainedValue() as String?,
              // 获取输入源类型
              let sourceTypePtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceType),
              let sourceType = Unmanaged<CFString>.fromOpaque(sourceTypePtr).takeUnretainedValue() as String?,
              // 获取本地化名称
              let localizedNamePtr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName),
              let localizedName = Unmanaged<CFString>.fromOpaque(localizedNamePtr).takeUnretainedValue() as String?,
              // 获取可选择状态
              let selectablePtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable),
              // 获取启用状态
              let enabledPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled) else {
            logger.error("Failed to get input source properties")
            return nil
        }
        
        let isSelectable = CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(selectablePtr).takeUnretainedValue())
        let isEnabled = CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(enabledPtr).takeUnretainedValue())
        
        return InputSourceProperties(
            sourceID: sourceID,
            sourceType: sourceType,
            localizedName: localizedName,
            isSelectable: isSelectable,
            isEnabled: isEnabled
        )
    }
    
    private static func isValidInputSourceType(_ sourceType: String) -> Bool {
        sourceType == (kTISTypeKeyboardLayout as String) || sourceType == (kTISTypeKeyboardInputMode as String)
    }
} 
