import Foundation

/// Shared HTTP for the collectors. Short timeout: a hung provider must not
/// stall the whole reading, and every caller turns a failure into a
/// `Provider.error` rather than propagating it.
enum HTTP {
    static let timeout: TimeInterval = 12

    struct StatusError: Error, LocalizedError {
        let code: Int
        var errorDescription: String? { "HTTP \(code)" }
    }

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = timeout
        c.httpShouldSetCookies = false
        return URLSession(configuration: c)
    }()

    static func request(
        _ url: String,
        method: String = "GET",
        headers: [String: String] = [:],
        jsonBody: Any? = nil
    ) throws -> URLRequest {
        guard let parsed = URL(string: url) else { throw URLError(.badURL) }
        var request = URLRequest(url: parsed, timeoutInterval: timeout)
        request.httpMethod = method
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        if let jsonBody {
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    /// Throws on any non-2xx, mirroring reqwest's `error_for_status` and
    /// urllib's raise-on-error.
    static func json(_ request: URLRequest) async throws -> Any {
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw StatusError(code: http.statusCode)
        }
        return try JSONSerialization.jsonObject(with: data)
    }
}

/// Untyped JSON access, so the ports read close to the serde_json/Python
/// originals instead of drowning in Codable structs for payloads we touch two
/// fields of.
extension Dictionary where Key == String, Value == Any {
    func dict(_ key: String) -> [String: Any]? { self[key] as? [String: Any] }
    func array(_ key: String) -> [Any]? { self[key] as? [Any] }
    func string(_ key: String) -> String? { self[key] as? String }
    func bool(_ key: String) -> Bool? { (self[key] as? NSNumber)?.boolValue }
    /// Numbers only — a JSON bool bridges to NSNumber and would read as 1/0.
    func number(_ key: String) -> Double? {
        guard let n = self[key] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        return n.doubleValue
    }
}
