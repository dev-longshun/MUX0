import AppKit

extension NSPasteboard.PasteboardType {
    /// mux0 sidebar workspace 拖拽类型。仅用于 WorkspaceListView 自身内部重排——
    /// 不跨进程、不支持外部拖入。与 .mux0Tab 命名对称。
    static let mux0Workspace = NSPasteboard.PasteboardType("com.mux0.workspace")
}
