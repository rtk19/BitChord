import UIKit
import WebKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = AppViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}

final class AppViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandlerWithReply {
    private var webView: WKWebView!
    private var audio: AudioManager!
    private let network = NativeHTTP()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.setURLSchemeHandler(AssetHandler(), forURLScheme: "bitchord")
        configuration.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: "bitchord")
        guard let scriptURL = Bundle.main.url(forResource: "Bridge", withExtension: "js"),
              let script = try? String(contentsOf: scriptURL, encoding: .utf8) else {
            fatalError("Missing bundled iOS bridge")
        }
        configuration.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.isInspectable = _isDebugAssertConfiguration()
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
        audio = AudioManager { [weak self] event in self?.emit("bitchord:audio", event) }
        NotificationCenter.default.addObserver(self, selector: #selector(resumed), name: UIApplication.didBecomeActiveNotification, object: nil)
        webView.load(URLRequest(url: URL(string: "bitchord://localhost/index.html")!))
    }

    @objc private func resumed() { audio?.refresh() }

    private func emit(_ name: String, _ data: [String: Any]) {
        guard let json = try? JSONSerialization.data(withJSONObject: data), let literal = String(data: json, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.dispatchEvent(new CustomEvent('\(name)', {detail: \(literal)}))", completionHandler: nil)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void) {
        guard message.frameInfo.isMainFrame, message.frameInfo.securityOrigin.protocol == "bitchord",
              message.frameInfo.securityOrigin.host == "localhost",
              let body = message.body as? [String: Any], body["protocol"] as? Int == 1,
              let method = body["method"] as? String, let params = body["params"] as? [String: Any] else {
            replyHandler(nil, "Untrusted bridge request")
            return
        }
        if method == "http.fetch" {
            Task { @MainActor in
                do { replyHandler(try await network.fetch(params), nil) }
                catch { replyHandler(nil, error.localizedDescription) }
            }
        } else {
            audio.handle(method, params: params, reply: replyHandler)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if url.scheme == "bitchord", url.host == "localhost" { decisionHandler(.allow); return }
        decisionHandler(.cancel)
        if navigationAction.navigationType == .linkActivated, ["https", "http"].contains(url.scheme ?? "") { UIApplication.shared.open(url) }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, ["https", "http"].contains(url.scheme ?? "") { UIApplication.shared.open(url) }
        return nil
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { webView.reload() }
}
