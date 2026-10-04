/// Makes soundbar error messages safe to log (pure logic).
public enum APIErrorText {
    /// The soundbar appends the full request (" - {…}") to error messages, including the access
    /// token and the device GUID. Only the part before it is kept: logs may end up in public issues.
    public static func sanitized(_ message: String, maxLength: Int = 200) -> String {
        String((message.components(separatedBy: " - {").first ?? "").prefix(maxLength))
    }
}
