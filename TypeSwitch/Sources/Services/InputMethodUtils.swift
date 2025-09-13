import Carbon
import Foundation
import OSLog

enum InputMethodUtils {
    @MainActor
    static func fetchInputMethods() throws -> [InputMethod] {
        // 确保在主线程调用
        guard Thread.isMainThread else {
            throw NSError(domain: "InputMethodUtils", code: 1001, userInfo: [NSLocalizedDescriptionKey: "必须在主线程调用"])
        }
        
        // 创建输入源列表
        guard let inputSourceList = TISCreateInputSourceList(nil, false)?.takeRetainedValue(),
              let inputSources = (inputSourceList as NSArray) as? [TISInputSource]
        else {
            throw NSError(domain: "InputMethodUtils", code: 1002, userInfo: [NSLocalizedDescriptionKey: "获取输入法列表失败"])
        }
        
        // 过滤和转换输入源
        let methods = inputSources.compactMap { source -> InputMethod? in
            guard let properties = getInputSourceProperties(source),
                  isValidInputSourceType(properties.sourceType),
                  properties.isSelectable, properties.isEnabled
            else {
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
            throw NSError(domain: "InputMethodUtils", code: 1001, userInfo: [NSLocalizedDescriptionKey: "必须在主线程调用"])
        }
        
        // 创建输入源列表
        guard let inputSourceList = TISCreateInputSourceList(nil, false)?.takeRetainedValue(),
              let inputSources = (inputSourceList as NSArray) as? [TISInputSource]
        else {
            throw NSError(domain: "InputMethodUtils", code: 1002, userInfo: [NSLocalizedDescriptionKey: "获取输入法列表失败"])
        }
        
        // 查找目标输入源
        guard let targetSource = inputSources.first(where: { source in
            guard let properties = getInputSourceProperties(source) else {
                return false
            }
            return properties.sourceID == inputMethodID
        }) else {
            throw NSError(domain: "InputMethodUtils", code: 1003, userInfo: [NSLocalizedDescriptionKey: "找不到指定的输入法"])
        }
        
        // 切换输入法前确保输入法是启用的
        guard let enabledPtr = TISGetInputSourceProperty(targetSource, kTISPropertyInputSourceIsEnabled),
              let enabled = Unmanaged<CFBoolean>.fromOpaque(enabledPtr).takeUnretainedValue() as? Bool,
              enabled
        else {
            throw NSError(domain: "InputMethodUtils", code: 1004, userInfo: [NSLocalizedDescriptionKey: "输入法未启用"])
        }
        
        let status = TISSelectInputSource(targetSource)
        if status != noErr {
            throw NSError(domain: "InputMethodUtils", code: 1005, userInfo: [NSLocalizedDescriptionKey: "切换输入法失败"])
        }
    }
    
    @MainActor
    static func getCurrentInputMethodId() throws -> String {
        // 确保在主线程调用
        guard Thread.isMainThread else {
            throw NSError(domain: "InputMethodUtils", code: 1001, userInfo: [NSLocalizedDescriptionKey: "必须在主线程调用"])
        }
        
        // 获取当前输入源
        guard let currentSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            throw NSError(domain: "InputMethodUtils", code: 1006, userInfo: [NSLocalizedDescriptionKey: "获取当前输入法失败"])
        }
        
        // 获取输入源属性
        guard let properties = getInputSourceProperties(currentSource) else {
            throw NSError(domain: "InputMethodUtils", code: 1006, userInfo: [NSLocalizedDescriptionKey: "获取当前输入法失败"])
        }
        
        return properties.sourceID
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
              let enabledPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled)
        else {
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
