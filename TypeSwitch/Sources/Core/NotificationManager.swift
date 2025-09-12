import SwiftUI
import AppKit

// Toast 视图
private struct ToastView: View {
    let message: String
    
    private var displayName: String {
        message.isEmpty ? "默认" : message
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "keyboard")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .font(.system(size: 14))
            Text("notification.switched".localized(with: displayName))
                .font(.system(size: 12))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(height: 32)
        .background {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                    .opacity(0.95)
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

@MainActor
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    private var window: NSWindow?
    private var hideTask: Task<Void, Never>?
    
    private init() {
        // 监听工作区变化，确保通知显示在正确的屏幕上
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceDidChangeScreen),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }
    
    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
    
    @objc private func workspaceDidChangeScreen() {
        updateWindowPosition()
    }
    
    private func updateWindowPosition() {
        guard let window = window, let screen = NSScreen.main else { return }
        let windowSize = window.frame.size
        
        // 使用 visibleFrame 可以自动考虑 Dock 栏的位置
        let screenFrame = screen.visibleFrame
        let padding: CGFloat = 16
        
        // 计算中下方位置
        let x = screenFrame.midX - windowSize.width / 2
        let y = screenFrame.minY + padding + 8 // 在可视区域底部上方一
        
        // 确保窗口完全在可视区域内
        let finalX = max(screenFrame.minX + padding, min(x, screenFrame.maxX - windowSize.width - padding))
        
        window.setFrameOrigin(NSPoint(x: finalX, y: y))
    }
    
    func showInputMethodSwitchNotification(inputMethodName: String) {
        // 取消之前的隐藏任务
        hideTask?.cancel()
        hideTask = nil
        
        // 如果已有窗口，先关闭
        window?.close()
        
        // 创建通知视图
        let contentView = ToastView(message: inputMethodName)
        let hostingView = NSHostingView(rootView: contentView)
        
        // 创建新的窗口
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 32),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false // 使用 SwiftUI 的阴影效果
        window.level = .statusBar
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        // 设置窗口内容
        window.contentView = hostingView
        window.setContentSize(hostingView.fittingSize)
        
        // 更新窗口位置
        self.window = window
        updateWindowPosition()
        
        // 显示窗口（带渐变动画）
        window.alphaValue = 0
        window.orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15 // 缩短动画时间，让反馈更快
            context.timingFunction = .init(name: .easeOut)
            window.animator().alphaValue = 1
        }
        
        // 创建隐藏任务
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1500)) // 缩短显示时间
            guard !Task.isCancelled else { return }
            await MainActor.run {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.15
                    context.timingFunction = .init(name: .easeIn)
                    self?.window?.animator().alphaValue = 0
                } completionHandler: {
                    self?.window?.close()
                    self?.window = nil
                }
            }
        }
    }
} 