import Foundation
import WebKit

final class AssetHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let root = Bundle.main.url(forResource: "Web", withExtension: nil), let requestURL = urlSchemeTask.request.url,
              requestURL.host == "localhost" else { urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist)); return }
        let path = requestURL.path == "/" ? "index.html" : String(requestURL.path.dropFirst())
        let file = root.appendingPathComponent(path).standardizedFileURL
        guard file.path.hasPrefix(root.path + "/"), let data = try? Data(contentsOf: file) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist)); return
        }
        let mime = ["html": "text/html", "js": "application/javascript", "css": "text/css", "json": "application/json", "svg": "image/svg+xml", "png": "image/png", "webp": "image/webp", "jpg": "image/jpeg", "woff2": "font/woff2", "wasm": "application/wasm"][file.pathExtension] ?? "application/octet-stream"
        urlSchemeTask.didReceive(URLResponse(url: requestURL, mimeType: mime, expectedContentLength: data.count, textEncodingName: mime.hasPrefix("text/") || file.pathExtension == "js" ? "utf-8" : nil))
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
