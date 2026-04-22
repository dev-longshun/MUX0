import AppKit

extension NSPasteboard.PasteboardType {
    /// mux0 Tab 拖拽类型。仅用于 TabBarView 自身内部重排——不跨进程、不支持外部拖入。
    static let mux0Tab = NSPasteboard.PasteboardType("com.mux0.tab")
}
