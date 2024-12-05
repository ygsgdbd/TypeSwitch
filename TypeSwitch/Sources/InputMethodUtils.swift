import Foundation
import Carbon

enum InputMethodError: Error {
    case failedToGetInputSources
    case inputMethodNotFound
    case switchFailed
}

enum InputMethodUtils {
    static func fetchInputMethods() throws -> [InputMethod] {
        // 创建输入源列表
        guard let inputSourceList = TISCreateInputSourceList(nil, false)?.takeRetainedValue(),
              let inputSources = (inputSourceList as NSArray) as? [TISInputSource] else {
            throw InputMethodError.failedToGetInputSources
        }
        
        // 过滤和转换输入源
        let methods = inputSources.compactMap { source -> InputMethod? in
            // 获取所有需要的属性
            guard let properties = getInputSourceProperties(source),
                  // 检查输入源类型是否符合要求
                  isValidInputSourceType(properties.sourceType),
                  // 检查输入源是否可用
                  properties.isSelectable && properties.isEnabled else {
                return nil
            }
            
            return InputMethod(id: properties.sourceID, name: properties.localizedName)
        }
        
        // 按本地化名称排序
        return methods.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    
    static func switchToInputMethod(_ inputMethodID: String) throws {
        // 创建输入源列表
        guard let inputSourceList = TISCreateInputSourceList(nil, false)?.takeRetainedValue(),
              let inputSources = (inputSourceList as NSArray) as? [TISInputSource] else {
            throw InputMethodError.failedToGetInputSources
        }
        
        // 查找目标输入源
        guard let targetSource = inputSources.first(where: { source in
            guard let properties = getInputSourceProperties(source) else {
                return false
            }
            return properties.sourceID == inputMethodID
        }) else {
            throw InputMethodError.inputMethodNotFound
        }
        
        // 切换输入法
        let status = TISSelectInputSource(targetSource)
        if status != noErr {
            throw InputMethodError.switchFailed
        }
    }
    
    // MARK: - Private Helpers
    
    private struct InputSourceProperties {
        let sourceID: String
        let sourceType: String
        let localizedName: String
        let isSelectable: Bool
        let isEnabled: Bool
    }
    
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