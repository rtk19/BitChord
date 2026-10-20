import Foundation

final class NativeHTTP {
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()

    func fetch(_ params: [String: Any]) async throws -> [String: Any] {
        guard let address = params["url"] as? String, let url = URL(string: address), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil else { throw URLError(.badURL) }
        let method = (params["method"] as? String ?? "GET").uppercased()
        guard ["GET", "POST", "HEAD"].contains(method) else { throw URLError(.unsupportedURL) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        for (name, value) in params["headers"] as? [String: String] ?? [:] {
            if !["host", "cookie", "content-length", "connection"].contains(name.lowercased()) { request.setValue(value, forHTTPHeaderField: name) }
        }
        if let body = params["body"] as? String {
            request.httpBody = params["bodyEncoding"] as? String == "base64" ? Data(base64Encoded: body) : body.data(using: .utf8)
        }
        let host = url.host ?? ""
        if host == "youtube.com" || host.hasSuffix(".youtube.com") || host.hasSuffix(".googlevideo.com") {
            request.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
            request.setValue("https://music.youtube.com/", forHTTPHeaderField: "Referer")
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            guard let name = key as? String, name.lowercased() != "set-cookie" else { continue }
            headers[name.lowercased()] = String(describing: value)
        }
        // URLSession has already decompressed the response.
        headers.removeValue(forKey: "content-encoding")
        headers.removeValue(forKey: "content-length")
        let textual = ["json", "text", "javascript", "xml"].contains { (http.mimeType ?? "").contains($0) }
        let text = textual ? String(data: data, encoding: .utf8) : nil
        return ["status": http.statusCode, "url": http.url?.absoluteString ?? address, "headers": headers,
                "body": text ?? data.base64EncodedString(), "bodyEncoding": text == nil ? "base64" : "text"]
    }
}
