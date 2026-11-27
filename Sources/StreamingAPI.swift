import Foundation
import Security

struct StreamingPairing: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var address: String
}

struct StreamingClient: Codable, Equatable, Identifiable {
    var name: String
    var uuid: String
    var enabled: Bool
    var id: String { uuid }
}

enum StreamingAPI {
    static func pairings(_ data: Data) -> [StreamingPairing] {
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = j["pairings"] as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard let id = row["id"] as? String else { return nil }
            return StreamingPairing(id: id, name: row["name"] as? String ?? "A device", address: row["address"] as? String ?? "")
        }
    }

    static func clients(_ data: Data) -> [StreamingClient] {
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = j["named_certs"] as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard let uuid = row["uuid"] as? String else { return nil }
            return StreamingClient(name: row["name"] as? String ?? "A device", uuid: uuid, enabled: row["enabled"] as? Bool ?? true)
        }
    }

    static func flag(_ data: Data) -> Bool {
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return j["status"] as? Bool ?? false
    }

    static func call(base: URL = StreamingPaths.webUI, user: String, password: String,
                     path: String, body: [String: Any]? = nil) throws -> Data {
        var r = URLRequest(url: base.appendingPathComponent(path), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        r.httpMethod = body == nil ? "GET" : "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let auth = Data("\(user):\(password)".utf8).base64EncodedString()
        r.setValue("Basic \(auth)", forHTTPHeaderField: "Authorization")   // no Origin or Referer: Sunshine allows local API calls
        if let body { r.httpBody = try? JSONSerialization.data(withJSONObject: body) }

        let session = URLSession(configuration: .ephemeral, delegate: LocalTrust(certificate: StreamingAPI.certificate()), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let done = DispatchSemaphore(value: 0)
        var got: Data?, reply: URLResponse?, failed: Error?
        session.dataTask(with: r) { data, response, error in
            got = data; reply = response; failed = error; done.signal()
        }.resume()
        done.wait()
        if let failed { throw failed }
        guard let http = reply as? HTTPURLResponse else { throw StreamingError.text("Sunshine didn't answer.") }
        guard (200..<300).contains(http.statusCode) else {
            throw StreamingError.text(http.statusCode == 401 ? "Sunshine didn't accept its own password. Turn Streaming off and on." : "Sunshine's TV settings weren't ready (\(http.statusCode)).")
        }
        return got ?? Data()
    }

    static func pairings(user: String, password: String) throws -> [StreamingPairing] {
        pairings(try call(user: user, password: password, path: "api/pin"))
    }

    static func clients(user: String, password: String) throws -> [StreamingClient] {
        clients(try call(user: user, password: password, path: "api/clients/list"))
    }

    static func pair(user: String, password: String, pairing: StreamingPairing, pin: String) throws -> Bool {
        flag(try call(user: user, password: password, path: "api/pin",
                      body: ["pairing_id": pairing.id, "pin": pin, "name": pairing.name]))
    }

    static func unpair(user: String, password: String, uuid: String) throws -> Bool {
        flag(try call(user: user, password: password, path: "api/clients/unpair", body: ["uuid": uuid]))
    }

    // The certificate Sunshine made for its own Web UI. Only that certificate is trusted on loopback.
    static func certificate() -> Data? {
        guard let pem = try? String(contentsOf: StreamingPaths.certificate, encoding: .utf8) else { return nil }
        let body = pem.split(whereSeparator: \.isNewline).filter { !$0.hasPrefix("-----") }.joined()
        guard let der = Data(base64Encoded: body), SecCertificateCreateWithData(nil, der as CFData) != nil else { return nil }
        return der
    }
}

// Sunshine's Web UI uses a certificate it makes for itself. Trust only that one, only on this Mac's loopback address.
private final class LocalTrust: NSObject, URLSessionDelegate {
    private let certificate: Data?

    init(certificate: Data?) { self.certificate = certificate }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              ["localhost", "127.0.0.1"].contains(challenge.protectionSpace.host),
              let expected = certificate, let trust = challenge.protectionSpace.serverTrust,
              let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let first = chain.first else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        let data = SecCertificateCopyData(first)
        guard let bytes = CFDataGetBytePtr(data) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        let served = Data(bytes: bytes, count: CFDataGetLength(data))
        guard served == expected else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
