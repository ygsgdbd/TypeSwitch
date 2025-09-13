import Carbon
import Foundation
import OSLog

/// 输入法工具类
/// 负责获取、切换和管理系统输入法
@MainActor
enum InputMethodUtils {
    
    /// 输入法相关错误
    enum InputMethodError: Error, LocalizedError {
        case failedToFetchInputMethods
        case inputMethodNotFound(String)
        case inputMethodNotEnabled(String)
        case failedToSwitchInputMethod(String)
        case failedToGetCurrentInputMethod
        
        var errorDescription: String? {
            switch self {
            case .failedToFetchInputMethods:
                return "获取输入法列表失败"
            case .inputMethodNotFound(let id):
                return "找不到指定的输入法: \(id)"
            case .inputMethodNotEnabled(let id):
                return "输入法未启用: \(id)"
            case .failedToSwitchInputMethod(let id):
                return "切换输入法失败: \(id)"
            case .failedToGetCurrentInputMethod:
                return "获取当前输入法失败"
            }
        }
    }
    
    
    // MARK: - 公共方法
    
    /// 获取所有可用的输入法
    /// - Returns: 输入法数组，按名称排序
    /// - Throws: Error 当获取失败时
    static func fetchInputMethods() throws -> [InputMethod] {
        let inputSources = try getInputSourceList()
        
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
    
    /// 切换到指定的输入法
    /// - Parameter inputMethodID: 输入法ID
    /// - Throws: Error 当切换失败时
    static func switchToInputMethod(_ inputMethodID: String) throws {
        let inputSources = try getInputSourceList()
        
        // 查找目标输入源
        guard let targetSource = inputSources.first(where: { source in
            guard let properties = getInputSourceProperties(source) else {
                return false
            }
            return properties.sourceID == inputMethodID
        }) else {
            throw InputMethodError.inputMethodNotFound(inputMethodID)
        }
        
        // 切换输入法前确保输入法是启用的
        guard let enabledPtr = TISGetInputSourceProperty(targetSource, kTISPropertyInputSourceIsEnabled),
              let enabled = Unmanaged<CFBoolean>.fromOpaque(enabledPtr).takeUnretainedValue() as? Bool,
              enabled
        else {
            throw InputMethodError.inputMethodNotEnabled(inputMethodID)
        }
        
        let status = TISSelectInputSource(targetSource)
        if status != noErr {
            throw InputMethodError.failedToSwitchInputMethod(inputMethodID)
        }
    }
    
    /// 获取当前激活的输入法ID
    /// - Returns: 当前输入法ID
    /// - Throws: Error 当获取失败时
    static func getCurrentInputMethodId() throws -> String {
        // 获取当前输入源
        guard let currentSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            throw InputMethodError.failedToGetCurrentInputMethod
        }
        
        // 获取输入源属性
        guard let properties = getInputSourceProperties(currentSource) else {
            throw InputMethodError.failedToGetCurrentInputMethod
        }
        
        return properties.sourceID
    }
    
    // MARK: - Private Helpers
    
    /// 获取输入源列表
    /// - Returns: 输入源数组
    /// - Throws: Error 当获取失败时
    private static func getInputSourceList() throws -> [TISInputSource] {
        guard let inputSourceList = TISCreateInputSourceList(nil, false)?.takeRetainedValue(),
              let inputSources = (inputSourceList as NSArray) as? [TISInputSource]
        else {
            throw InputMethodError.failedToFetchInputMethods
        }
        
        return inputSources
    }
    
    
    /// 获取输入源属性
    /// - Parameter source: 输入源
    /// - Returns: 输入源属性，失败时返回nil
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
    
    /// 检查输入源类型是否有效
    /// - Parameter sourceType: 输入源类型
    /// - Returns: 是否为有效的输入源类型
    private static func isValidInputSourceType(_ sourceType: String) -> Bool {
        sourceType == (kTISTypeKeyboardLayout as String) || sourceType == (kTISTypeKeyboardInputMode as String)
    }
}

