import SwiftUI
import AppKit

/// 把 SwiftUI 内容延伸到 NSWindow 的 traffic-light 区域下，去掉 hidden-titlebar 留下的顶部空白条。
struct WindowAccessor: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        DispatchQueue.main.async {
            if let w = v.window { configure(w) }
        }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let w = nsView.window { configure(w) }
        }
    }
}

extension View {
    /// 让窗口允许内容延伸到标题栏区域，并按 background-opacity 切换窗口本体的不透明度。
    /// - Parameter backgroundOpacity: 当 < 1 时把 window.isOpaque 设为 false 且
    ///   backgroundColor = .clear，让 ghostty surface 的 alpha 透到桌面；= 1 时复原。
    /// - Parameter blurRadius: 仅用于 SwiftUI 依赖跟踪 —— 模糊半径的实际应用由
    ///   ghostty 在 `applyWindowBackgroundBlur` 时从自己的 config 里读。把它作为
    ///   参数传入是为了让 body 观察到值变化时重新渲染，触发 updateNSView 回调，
    ///   否则单独改模糊设置不会立即生效（要等 opacity 一起变才冒泡刷新）。
    /// - Parameter onWindow: 每次 configure 都会回调 —— ContentView 借此拿窗口指针
    ///   递给 GhosttyBridge.applyWindowBackgroundBlur。
    func mux0FullSizeContent(
        backgroundOpacity: CGFloat = 1.0,
        blurRadius: CGFloat = 0,
        onWindow: @escaping (NSWindow) -> Void = { _ in }
    ) -> some View {
        background(
            WindowAccessor { window in
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
                window.styleMask.insert(.fullSizeContentView)
                window.isMovableByWindowBackground = false
                if let toolbar = window.toolbar {
                    toolbar.isVisible = false
                }
                let opaque = backgroundOpacity >= 1.0
                window.isOpaque = opaque
                window.backgroundColor = opaque ? nil : .clear
                window.hasShadow = true
                _ = blurRadius
                onWindow(window)
            }
        )
    }
}
