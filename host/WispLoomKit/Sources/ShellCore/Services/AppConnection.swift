import Foundation

/// What a page asks of its own window.
public enum WindowRequest: Sendable, Equatable {
    case title(String, subtitle: String?)
    /// Content height the page wants (settings panes); the host animates the window to it.
    case contentHeight(Double)
    /// The window's native toolbar, described by the page.
    case toolbar(ToolbarSpec)
    /// A native menu for the page's context menu, shown at the pointer.
    case contextMenu([ToolbarMenuItem])
}

/// One app window's link to its host session. The page speaks the backend's JSON Lines dialect over a
/// WebKit message handler: requests `{id, method, params}`, answers `{id, event|result|error}`.
@MainActor
public protocol AppConnection: AnyObject {
    var appID: AppID { get }
    var kind: WindowInstance.Kind { get }
    /// Folder the page's files are served from.
    var directory: URL { get }
    /// Entry script, relative to `directory` (the stylesheet is the same name with `.css`).
    var script: String { get }
    /// JSON object the page finds in `window.__wisp_boot` before any script runs.
    var bootstrap: String { get }
    /// Host → page: a JSON array of messages, batched once per run-loop turn.
    var deliver: (@MainActor (String) -> Void)? { get set }
    /// Dev hot reload: the page should load again.
    var reload: (@MainActor () -> Void)? { get set }
    var onWindow: (@MainActor (WindowRequest) -> Void)? { get set }
    /// Page → host: one JSON message.
    func receive(_ json: String)
    /// Host → page: one message on the same batched channel as replies (toolbar actions, search).
    func push(_ message: [String: JSONValue])
    /// The window is gone; in-flight calls are cancelled. Safe to call twice.
    func close()
}
