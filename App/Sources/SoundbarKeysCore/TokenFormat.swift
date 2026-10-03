import Foundation

/// Pure helpers around the stored tokens (no Keychain, no network).
public enum TokenFormat {
    /// Expiry date from a JWT's `exp` claim, without verifying the signature
    /// (only used to decide when to refresh; the soundbar verifies the token itself).
    public static func expiry(ofJWT jwt: String) -> Date? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var b64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        b64 += String(repeating: "=", count: (4 - b64.count % 4) % 4)
        guard let data = Data(base64Encoded: b64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = json["exp"] as? Double else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    /// Splits a string into chunks of at most `size` characters
    /// (`security -i` only accepts lines up to about 4 KB).
    public static func chunks(of text: String, size: Int) -> [String] {
        precondition(size > 0, "chunk size must be positive")
        var parts: [String] = []
        var index = text.startIndex
        while index < text.endIndex {
            let end = text.index(index, offsetBy: size, limitedBy: text.endIndex) ?? text.endIndex
            parts.append(String(text[index..<end]))
            index = end
        }
        return parts
    }
}
