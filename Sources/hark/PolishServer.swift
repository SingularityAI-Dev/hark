import Foundation
import Security

/// An OpenAI-compatible chat server used for polish instead of Apple's on-device model,
/// such as FreeLLMAPI at http://localhost:3001/v1. Whatever is dictated is sent to it, and
/// FreeLLMAPI forwards it to free cloud providers, so it is only used when a URL is set.
struct PolishServer {
    var baseURL: URL
    var model: String
    var key: String?

    /// The server from Settings, or from HARK_POLISH_URL, HARK_POLISH_MODEL and
    /// HARK_POLISH_KEY when those are set (used by `make eval`). Nil means use Apple's model.
    static var configured: PolishServer? {
        let environment = ProcessInfo.processInfo.environment
        let address = environment["HARK_POLISH_URL"] ?? Settings.shared.polishServerURL
        guard let url = URL(string: address.trimmingCharacters(in: .whitespaces)), url.scheme != nil else { return nil }
        let model = environment["HARK_POLISH_MODEL"] ?? Settings.shared.polishServerModel
        return PolishServer(
            baseURL: url, model: model.isEmpty ? "auto" : model,
            key: environment["HARK_POLISH_KEY"] ?? Keychain.polishServerKey)
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    func complete(instructions: String, prompt: String, timeout: TimeInterval = 10) async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"), timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key, !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "temperature": 0,
            "messages": [
                ["role": "system", "content": instructions],
                ["role": "user", "content": prompt],
            ],
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Failure(description: "polish server answered HTTP \(status)") }
        guard
            let body = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = body["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else { throw Failure(description: "polish server reply had no message") }
        return content
    }
}

/// The polish server's API key, kept in the login keychain rather than in preferences.
enum Keychain {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "dev.hark.app",
        kSecAttrAccount as String: "polish-server-key",
    ]

    static var polishServerKey: String? {
        get {
            var item: CFTypeRef?
            var search = query
            search[kSecReturnData as String] = true
            guard SecItemCopyMatching(search as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }
        set {
            SecItemDelete(query as CFDictionary)
            guard let newValue, !newValue.isEmpty else { return }
            var item = query
            item[kSecValueData as String] = Data(newValue.utf8)
            SecItemAdd(item as CFDictionary, nil)
        }
    }
}
