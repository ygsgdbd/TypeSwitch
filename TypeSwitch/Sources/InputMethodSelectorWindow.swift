import SwiftUI
import AppKit
import Carbon

class InputMethodSelectorWindow: NSWindow {
    static let shared = InputMethodSelectorWindow()
    private var fadeOutWorkItem: DispatchWorkItem?
    private var keyMonitor: Any?
    private var keyUpMonitor: Any?
    private var isModifierKeysPressed = false
    
    private init() {
        // 初始化时使用主显示器的尺寸，实际显示时会更新位置
        let screenSize = NSScreen.main?.frame.size ?? .zero
        let windowSize = NSSize(width: 280, height: 180)
        let windowRect = NSRect(
            x: 0,
            y: 0,
            width: windowSize.width,
            height: windowSize.height
        )
        
        super.init(
            contentRect: windowRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.level = .floating
        self.ignoresMouseEvents = true
        self.alphaValue = 0
        self.canBecomeKey = false
        self.canBecomeMain = false
        
        let contentView = NSHostingView(rootView: InputMethodSelectorView())
        self.contentView = contentView
        
        setupKeyMonitors()
    }
    
    override var canBecomeKey: Bool {
        get { return false }
        set { }
    }
    
    override var canBecomeMain: Bool {
        get { return false }
        set { }
    }
    
    private func setupKeyMonitors() {
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let flags = event.modifierFlags
            let isControlShiftPressed = flags.contains([.control, .shift])
            
            if self?.isModifierKeysPressed == true && !isControlShiftPressed {
                self?.isModifierKeysPressed = false
                self?.startFadeOutTimer()
            } else if isControlShiftPressed {
                self?.isModifierKeysPressed = true
            }
        }
        
        keyUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] event in
            if event.keyCode == 49 { // 空格键的键码
                if !(self?.isModifierKeysPressed ?? false) {
                    self?.startFadeOutTimer()
                }
            }
        }
    }
    
    deinit {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = keyUpMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
    
    private func startFadeOutTimer() {
        fadeOutWorkItem?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                self.animator().alphaValue = 0
            } completionHandler: {
                self.orderOut(nil)
            }
        }
        fadeOutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }
    
    private func getActiveScreen() -> NSScreen? {
        // 获取当前鼠标所在的屏幕
        let mouseLocation = NSEvent.mouseLocation
        let screens = NSScreen.screens
        
        // 首先检查鼠标位置所在的屏幕
        if let screenWithMouse = screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
            return screenWithMouse
        }
        
        // 如果找不到鼠标所在屏幕，尝试获取当前激活窗口所在的屏幕
        if let keyWindow = NSApp.keyWindow?.screen {
            return keyWindow
        }
        
        // 如果都找不到，返回主屏幕
        return NSScreen.main
    }
    
    func showWithInputMethod(_ inputMethod: InputMethod?) {
        fadeOutWorkItem?.cancel()
        isModifierKeysPressed = true
        
        // 获取当前活跃的屏幕
        if let activeScreen = getActiveScreen() {
            let screenFrame = activeScreen.frame
            let windowSize = NSSize(width: 280, height: 180)
            
            // 计算窗口在当前屏幕上的位置
            let windowX = screenFrame.origin.x + (screenFrame.width - windowSize.width) / 2
            let windowY = screenFrame.origin.y + screenFrame.height * 0.6
            
            self.setFrame(NSRect(
                x: windowX,
                y: windowY,
                width: windowSize.width,
                height: windowSize.height
            ), display: true)
        }
        
        NotificationCenter.default.post(
            name: Notification.Name("CurrentInputMethodChanged"),
            object: nil,
            userInfo: ["inputMethod": inputMethod as Any]
        )
        
        self.orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            self.animator().alphaValue = 1
        }
    }
}

struct InputMethodSelectorView: View {
    @State private var currentInputMethod: InputMethod?
    @State private var allInputMethods: [InputMethod] = []
    
    private let defaultInputMethod = InputMethod(id: "", name: "跟随系统")
    
    var body: some View {
        ZStack {
            // 背景
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .windowBackgroundColor))
                .opacity(0.95)
                .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 0)
            
            VStack(spacing: 0) {
                // 标题
                Text("输入法")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                
                Divider()
                    .padding(.horizontal, 1)
                
                ScrollView {
                    VStack(spacing: 0) {
                        // 默认选项
                        InputMethodRow(
                            method: defaultInputMethod,
                            isSelected: currentInputMethod == nil,
                            isDefault: true
                        )
                        
                        if !allInputMethods.isEmpty {
                            Divider()
                                .padding(.horizontal, 1)
                        }
                        
                        // 输入法列表
                        ForEach(allInputMethods) { method in
                            InputMethodRow(
                                method: method,
                                isSelected: method.id == currentInputMethod?.id,
                                isDefault: false
                            )
                            
                            if method.id != allInputMethods.last?.id {
                                Divider()
                                    .padding(.horizontal, 1)
                            }
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
        .frame(width: 280, height: 180)
        .onAppear {
            Task {
                do {
                    allInputMethods = try await InputMethodUtils.fetchInputMethods()
                } catch {
                    print("Failed to fetch input methods: \(error)")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CurrentInputMethodChanged"))) { notification in
            if let inputMethod = notification.userInfo?["inputMethod"] as? InputMethod {
                self.currentInputMethod = inputMethod
            } else {
                // 如果收到的是 nil，表示切换到默认选项
                self.currentInputMethod = nil
            }
        }
    }
}

struct InputMethodRow: View {
    let method: InputMethod
    let isSelected: Bool
    let isDefault: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            // 选中指示器
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.accentColor)
                    .frame(width: 16)
            } else {
                Spacer()
                    .frame(width: 16)
            }
            
            // 图标
            if isDefault {
                Image(systemName: "globe")
                    .font(.system(size: 14))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .frame(width: 20)
            } else {
                Image(systemName: "keyboard")
                    .font(.system(size: 14))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .frame(width: 20)
            }
            
            // 输入法名称
            Text(method.name)
                .font(.system(size: 13))
                .foregroundColor(isSelected ? .accentColor : Color(nsColor: .labelColor))
            
            Spacer()
        }
        .frame(height: 32)
        .contentShape(Rectangle())
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(nsColor: .selectedControlColor))
                .opacity(isSelected ? 0.15 : 0)
                .padding(.horizontal, 4)
        )
    }
} 