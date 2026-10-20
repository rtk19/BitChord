import SwiftUI
import WebKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--reset-library") { UserDefaults.standard.removeObject(forKey: LocalLibrary.key) }
        #endif
        let model = MusicModel()
        let host = UIHostingController(rootView: RootView().environmentObject(model))
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        self.window = window
        // Only catalogue/resolver logic runs in WebKit. All screens are SwiftUI.
        let runtime = model.service.webView!
        runtime.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        runtime.isHidden = true
        runtime.accessibilityElementsHidden = true
        host.view.addSubview(runtime)
        model.start()
        return true
    }
}

@MainActor
final class CatalogueService: NSObject, WKScriptMessageHandlerWithReply, WKNavigationDelegate {
    private(set) var webView: WKWebView!
    private let network = NativeHTTP()
    var ready = false
    var audio: AudioManager!
    var onTermination: (() -> Void)?

    override init() {
        super.init()
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(AssetHandler(), forURLScheme: "bitchord")
        config.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: "bitchord")
        let url = Bundle.main.url(forResource: "Bridge", withExtension: "js")!
        let script = try! String(contentsOf: url, encoding: .utf8)
        config.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.isInspectable = _isDebugAssertConfiguration()
    }

    func start() { webView.load(URLRequest(url: URL(string: "bitchord://localhost/index.html")!)) }

    func request<T: Decodable>(_ method: String, _ params: [String: Any] = [:], as type: T.Type = T.self) async throws -> T {
        for _ in 0..<150 {
            if ready { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        guard ready else { throw CatalogueError.message("The music engine could not start. Please reopen BitChord.") }
        try Task.checkCancellation()
        let value = try await webView.callAsyncJavaScript("return JSON.stringify(await window.__bcService(method, params))", arguments: ["method": method, "params": params], in: nil, contentWorld: .page)
        guard let json = value as? String, let data = json.data(using: .utf8) else { throw CatalogueError.message("The music service returned an empty response.") }
        return try JSONDecoder().decode(type, from: data)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void) {
        guard message.frameInfo.isMainFrame, message.frameInfo.securityOrigin.protocol == "bitchord",
              message.frameInfo.securityOrigin.host == "localhost",
              let body = message.body as? [String: Any], body["protocol"] as? Int == 1,
              let method = body["method"] as? String, let params = body["params"] as? [String: Any] else {
            replyHandler(nil, "Untrusted bridge request"); return
        }
        if method == "service.ready" { ready = true; replyHandler([:], nil) }
        else if method == "http.fetch" {
            Task { do { replyHandler(try await network.fetch(params), nil) } catch { replyHandler(nil, error.localizedDescription) } }
        } else { audio.handle(method, params: params, reply: replyHandler) }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let url = navigationAction.request.url
        decisionHandler(url?.scheme == "bitchord" && url?.host == "localhost" ? .allow : .cancel)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        ready = false
        onTermination?()
        webView.reload()
    }
}

enum CatalogueError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}
