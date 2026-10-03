import Foundation

enum Config {
    // MARK: Soundbar API

    /// Bonjour service advertised by Bose "ECO2" products (Soundbar 500/700/900/Ultra, Home Speakers …).
    static let bonjourType = "_bose-passport._tcp"
    /// Port of the local WebSocket API.
    static let apiPort = 8082
    /// Product identifier the Bose iOS app sends when connecting (same as pybose).
    static let productQuery = "product=Madrid-iOS:31019F02-F01F-4E73-B495-B96D33AD3664"

    // MARK: Timing

    static let discoveryTimeoutSeconds: TimeInterval = 5
    static let resolveTimeoutSeconds: TimeInterval = 5
    /// Keep-alive ping; a failed ping reveals a dead connection (e.g. soundbar unplugged).
    static let pingIntervalSeconds: TimeInterval = 30
    /// Reconnect backoff doubles from 1 s up to this value.
    static let maxReconnectDelaySeconds: TimeInterval = 30
    /// Give the network a moment after wake before reconnecting.
    static let wakeReconnectDelaySeconds: TimeInterval = 2
    /// Retry after a failed sign-in/token refresh (e.g. the internet was down).
    static let loginRetryDelaySeconds: TimeInterval = 5 * 60
    /// Refresh the access token when it expires in less than this.
    static let tokenRefreshMarginSeconds: TimeInterval = 15 * 60
    /// How often to check the token proactively (keeps the Azure refresh token in use).
    static let tokenCheckIntervalSeconds: TimeInterval = 30 * 60
    /// How often to check whether Accessibility access was granted.
    static let accessibilityPollSeconds: TimeInterval = 2
    static let hudVisibleSeconds: TimeInterval = 1.5
    /// How often quiet hours are re-evaluated (start/end take effect within this time).
    static let quietHoursCheckSeconds: TimeInterval = 30
    /// After a volume key press, key routing is logged for this long (diagnostics).
    static let keyDiagnosticsWindowSeconds: TimeInterval = 30

    // MARK: Settings

    static let stepChoices = [1, 2, 4, 6]
    static let defaultStep = 4
    /// Default for the maximum volume (protection against "suddenly very loud").
    static let defaultMaxVolume = 40
    /// Range of the "maximum volume" setting.
    static let minimumMaxVolume = 5
    static let defaultQuietStartMinute = 22 * 60
    static let defaultQuietEndMinute = 7 * 60
    static let defaultQuietMaxVolume = 20

    // MARK: Keychain

    static let keychainService = "SoundbarKeys"
    /// `security -i` only accepts lines up to about 4 KB, so tokens are stored in chunks.
    static let keychainChunkCharacters = 3000

    // MARK: Links

    static let githubURL = URL(string: "https://github.com/Niko11111/SoundbarKeys")!
    static let kofiURL = URL(string: "https://ko-fi.com/niko11111")!
}
