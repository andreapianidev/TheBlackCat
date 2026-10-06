import AppKit
import Foundation
import Security

/// The Agnes API key, kept in the login keychain.
enum AgnesKey {
    private static let service = "app.andreapiani.theblackcat"
    private static let account = "agnes"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func load() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data,
              let key = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty
        else { return nil }
        return key
    }

    static func save(_ key: String) {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, let data = key.data(using: .utf8) else { return }
        let update: [String: Any] = [kSecValueData as String: data]
        if SecItemUpdate(query as CFDictionary, update as CFDictionary) == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrLabel as String] = "The Black Cat, chiave Agnes"
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static func delete() {
        SecItemDelete(query as CFDictionary)
    }

    /// Reads AGNES_API_KEY from ~/.secrets/agnes-ai.env and stores it in the keychain.
    static func importFromVault() -> Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".secrets/agnes-ai.env")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
        for raw in text.components(separatedBy: .newlines) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("export ") { line = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
            guard line.hasPrefix("AGNES_API_KEY="), let eq = line.firstIndex(of: "=") else { continue }
            var value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if let hash = value.range(of: " #") { value = String(value[..<hash.lowerBound]) }
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'").union(.whitespaces))
            guard !value.isEmpty else { continue }
            save(value)
            return load() == value
        }
        return false
    }
}

/// Minimal client for the Agnes gateway (OpenAI compatible chat completions).
enum AgnesClient {
    enum Failure: Error { case noKey, badImage, status(Int), badReply }

    private static let endpoint = URL(string: "https://apihub.agnes-ai.com/v1/chat/completions")!
    private static let model = "agnes-2.5-flash"
    private static let reasoningHeadroom = 1024

    static func chat(system: String, user: String, image: CGImage? = nil, maxTokens: Int = 120) async throws -> String {
        guard let key = AgnesKey.load() else { throw Failure.noKey }

        let userContent: Any
        if let image {
            guard let b64 = jpegBase64(image) else { throw Failure.badImage }
            userContent = [
                ["type": "text", "text": user],
                ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(b64)"]],
            ]
        } else {
            userContent = user
        }
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": userContent],
            ],
            "temperature": 1.0,
            // agnes-2.5-flash reasons by default and the reasoning counts against max_tokens:
            // ask it not to think, and leave headroom in case the gateway ignores the switch.
            "chat_template_kwargs": ["enable_thinking": false],
            "max_tokens": maxTokens + reasoningHeadroom,
        ]

        var req = URLRequest(url: endpoint, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw Failure.status(code) }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              var content = message["content"] as? String
        else { throw Failure.badReply }
        if let end = content.range(of: "</think>") { content = String(content[end.upperBound...]) }
        content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { throw Failure.badReply }
        return content
    }

    /// Scales to at most 768 px wide and encodes as JPEG at quality 0.6.
    private static func jpegBase64(_ image: CGImage) -> String? {
        let scale = min(1, 768 / CGFloat(max(image.width, 1)))
        let w = max(Int(CGFloat(image.width) * scale), 1)
        let h = max(Int(CGFloat(image.height) * scale), 1)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let scaled = ctx.makeImage(),
              let jpeg = NSBitmapImageRep(cgImage: scaled).representation(using: .jpeg, properties: [.compressionFactor: 0.6])
        else { return nil }
        return jpeg.base64EncodedString()
    }
}
