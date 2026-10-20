import SwiftUI
import WebKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private(set) var model: MusicModel!
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--reset-library") { UserDefaults.standard.removeObject(forKey: LocalLibrary.key) }
        #endif
        model = MusicModel()
        let host = UIHostingController(rootView: RootView().environmentObject(model!))
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
    private var pending: [String: CheckedContinuation<String, Error>] = [:]
    private var deadlines: [String: DispatchWorkItem] = [:]
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
        let id = UUID().uuidString
        let encoded = try JSONSerialization.data(withJSONObject: ["id": id, "method": method, "params": params])
        let arguments = String(decoding: encoded, as: UTF8.self)
        // The classic ObjC evaluation API avoids a strong dependency on the
        // Swift WebKit overlay, absent in the iOS 18.4/18.5 simulator runtime.
        // Promise replies travel over the already authenticated message bridge.
        let script = """
        (() => {
          const request = \(arguments);
          Promise.resolve().then(() => window.__bcService(request.method, request.params))
            .then(value => ({value}), error => ({error: error instanceof Error ? error.message : String(error)}))
            .then(response => window.__bcNativeCall('service.result', {id: request.id, data: JSON.stringify(response)}));
        })();
        """
        let json: String = try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                pending[id] = continuation
                let deadline = DispatchWorkItem { [weak self] in
                    self?.settle(id, .failure(CatalogueError.message("The music service timed out. Please try again.")))
                }
                deadlines[id] = deadline
                DispatchQueue.main.asyncAfter(deadline: .now() + (method == "resolve" ? 180 : 90), execute: deadline)
                webView.evaluateJavaScript(script) { [weak self] _, error in
                    if let error { self?.settle(id, .failure(error)) }
                }
            }
        }, onCancel: { [weak self] in
            Task { @MainActor in self?.settle(id, .failure(CancellationError())) }
        })
        let data = Data(json.utf8)
        let envelope = try JSONDecoder().decode(ServiceEnvelope<T>.self, from: data)
        if let error = envelope.error { throw CatalogueError.message(error) }
        guard let result = envelope.value else { throw CatalogueError.message("The music service returned an empty response.") }
        return result
    }

    private func settle(_ id: String, _ result: Result<String, Error>) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        deadlines.removeValue(forKey: id)?.cancel()
        continuation.resume(with: result)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void) {
        guard message.frameInfo.isMainFrame, message.frameInfo.securityOrigin.protocol == "bitchord",
              message.frameInfo.securityOrigin.host == "localhost",
              let body = message.body as? [String: Any], body["protocol"] as? Int == 1,
              let method = body["method"] as? String, let params = body["params"] as? [String: Any] else {
            replyHandler(nil, "Untrusted bridge request"); return
        }
        if method == "service.ready" { ready = true; replyHandler([:], nil) }
        else if method == "service.result" {
            guard let id = params["id"] as? String, let data = params["data"] as? String else { replyHandler(nil, "Invalid engine reply"); return }
            settle(id, .success(data)); replyHandler([:], nil)
        }
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
        for id in Array(pending.keys) { settle(id, .failure(CatalogueError.message("The music engine restarted. Please try again."))) }
        onTermination?()
        webView.reload()
    }
}

enum CatalogueError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}

private struct ServiceEnvelope<T: Decodable>: Decodable {
    let value: T?
    let error: String?
}
