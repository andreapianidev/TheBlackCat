import Foundation

/// Minimal client for DeepSeek (OpenAI compatible chat completions), text only.
/// The key comes from the keychain (VaultKey.deepSeek), never from the repository.
enum DeepSeekClient {
    enum Failure: Error { case noKey, status(Int), badReply }

    private static let endpoint = URL(string: "https://api.deepseek.com/chat/completions")!
    private static let model = "deepseek-v4-flash"

    static var hasKey: Bool { VaultKey.deepSeek.load() != nil }

    static func chat(system: String, user: String, maxTokens: Int = 120, json: Bool = false) async throws -> String {
        guard let key = VaultKey.deepSeek.load() else { throw Failure.noKey }
        var body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
            "temperature": 1.0,
            "max_tokens": maxTokens,
            // Quick answers: no reasoning pass before replying.
            "thinking": ["type": "disabled"],
        ]
        if json { body["response_format"] = ["type": "json_object"] }

        var req = URLRequest(url: endpoint, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw Failure.status(code) }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = (message["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty
        else { throw Failure.badReply }
        return content
    }
}

/// Which cloud brain, if any, the user picked in Settings ("apple" means none).
enum CloudBrain: String {
    case agnes, deepseek

    var ready: Bool {
        switch self {
        case .agnes: return AgnesKey.load() != nil
        case .deepseek: return DeepSeekClient.hasKey
        }
    }

    func chat(system: String, user: String, maxTokens: Int = 120, json: Bool = false) async throws -> String {
        switch self {
        case .agnes: return try await AgnesClient.chat(system: system, user: user, maxTokens: maxTokens)
        case .deepseek: return try await DeepSeekClient.chat(system: system, user: user, maxTokens: maxTokens, json: json)
        }
    }
}
