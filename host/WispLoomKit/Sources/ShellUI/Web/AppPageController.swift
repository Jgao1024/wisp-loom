import AppKit
import ShellCore
import WebKit

/// Hosts one app window's page. The page is plain web content served from the app's folder through the
/// `wisp://app/` scheme (no file access granted to WebKit); everything else goes through one message handler.
@MainActor
public final class AppPageController: NSViewController {
    public let connection: any AppConnection
    private let webView: WKWebView
    private lazy var toolbarController = NativeToolbarController(
        onAction: { [weak self] id in
            self?.connection.push(["type": .string("toolbarAction"), "id": .string(id)])
        },
        onSearch: { [weak self] text in
            self?.connection.push(["type": .string("toolbarSearch"), "text": .string(text)])
        },
        onTab: { [weak self] id in
            self?.connection.push(["type": .string("tabSelected"), "id": .string(id)])
        })

    public init(connection: any AppConnection) {
        self.connection = connection
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(PageScheme(connection: connection), forURLScheme: PageScheme.name)
        let boot = WKUserScript(
            source: "window.__wisp_boot = \(connection.bootstrap);", injectionTime: .atDocumentStart,
            forMainFrameOnly: true)
        config.userContentController.addUserScript(boot)
        webView = WKWebView(frame: .zero, configuration: config)
        super.init(nibName: nil, bundle: nil)

        config.userContentController.add(MessageRelay(connection), name: "wisp")
        webView.navigationDelegate = self
        #if DEBUG
            webView.isInspectable = true
        #endif
        connection.deliver = { [weak webView] batch in
            webView?.evaluateJavaScript("window.__wisp_recv(\(batch))", completionHandler: nil)
        }
        connection.reload = { [weak webView] in webView?.reload() }
        connection.onWindow = { [weak self] in self?.handle($0) }
    }

    private func handle(_ request: WindowRequest) {
        switch request {
        case .title(let title, let subtitle):
            view.window?.title = title
            view.window?.subtitle = subtitle ?? ""
        case .contentHeight(let height):
            guard let window = view.window else { return }
            var frame = window.frameRect(
                forContentRect: CGRect(x: 0, y: 0, width: window.contentLayoutRect.width, height: height))
            frame.origin = CGPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)  // keep the top edge
            window.setFrame(frame, display: true, animate: window.isVisible)
        case .toolbar(let spec):
            toolbarController.apply(spec)
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// A sidebar-material view sits behind a transparent page: columns that paint nothing show system vibrancy,
    /// columns with a background stay opaque.
    public override func loadView() {
        let container = NSVisualEffectView()
        container.material = .sidebar
        container.blendingMode = .behindWindow
        container.state = .followsWindowActiveState
        webView.setValue(false, forKey: "drawsBackground")
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        view = container
        webView.load(URLRequest(url: URL(string: "\(PageScheme.name)://app/index.html")!))
    }

    /// Every window gets a toolbar even before the page sends a spec, so the titlebar height is stable.
    /// Settings windows use the preference style: native titlebar, then the tab row, then the page.
    public override func viewDidAppear() {
        super.viewDidAppear()
        guard let window = view.window else { return }
        toolbarController.install(on: window, style: connection.kind == .settings ? .preference : .unified)
    }

    /// Break the handler → connection reference and release the backend link.
    public func tearDown() {
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
        connection.close()
    }
}

extension AppPageController: WKNavigationDelegate {
    /// Pages never leave their own origin; links open in the default browser.
    public func webView(
        _ webView: WKWebView, decidePolicyFor action: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        guard let url = action.request.url, url.scheme != PageScheme.name, url.scheme != "about" else { return .allow }
        if action.navigationType == .linkActivated { NSWorkspace.shared.open(url) }
        return .cancel
    }
}

/// Forwards page messages without WebKit retaining the connection strongly.
private final class MessageRelay: NSObject, WKScriptMessageHandler {
    private weak var connection: (any AppConnection)?

    @MainActor init(_ connection: any AppConnection) { self.connection = connection }

    @MainActor func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        if let json = message.body as? String { connection?.receive(json) }
    }
}

/// Serves `index.html` (synthesised) and the app folder's files; anything outside the folder is a 404.
private final class PageScheme: NSObject, WKURLSchemeHandler {
    static let name = "wisp"
    private let connection: any AppConnection

    @MainActor init(connection: any AppConnection) { self.connection = connection }

    @MainActor func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        let path = task.request.url?.path ?? "/"
        guard let (data, type) = resource(for: path) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let headers = ["Content-Type": type, "Content-Length": "\(data.count)", "Cache-Control": "no-store"]
        task.didReceive(
            HTTPURLResponse(url: task.request.url!, statusCode: 200, httpVersion: nil, headerFields: headers)!)
        task.didReceive(data)
        task.didFinish()
    }

    @MainActor func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}

    @MainActor private func resource(for path: String) -> (Data, String)? {
        if path == "/index.html" { return (Data(indexHTML.utf8), "text/html; charset=utf-8") }
        if path.hasPrefix("/__symbol/") { return SymbolImage.png(named: String(path.dropFirst("/__symbol/".count))) }
        let root = connection.directory.standardizedFileURL
        let file = root.appendingPathComponent(String(path.dropFirst())).standardizedFileURL
        guard file.path.hasPrefix(root.path + "/"), let data = try? Data(contentsOf: file) else { return nil }
        return (data, Self.mimeTypes[file.pathExtension] ?? "application/octet-stream")
    }

    @MainActor private var indexHTML: String {
        let style = (connection.script as NSString).deletingPathExtension + ".css"
        return """
            <!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width">
            <link rel="stylesheet" href="\(style)"><body><script src="\(connection.script)"></script>
            """
    }

    private static let mimeTypes = [
        "js": "text/javascript", "css": "text/css", "json": "application/json", "svg": "image/svg+xml",
        "png": "image/png", "jpg": "image/jpeg", "woff2": "font/woff2",
    ]
}
