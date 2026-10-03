import AppKit
import WebKit

/// Phone-sized window showing Bose's sign-in page. The page is designed for the narrow web view
/// of the Bose app and scales its text with the window width, so a large window looks oversized.
///
/// It waits for the redirect to the app callback (`bosemusic://auth/callback?…`) and returns it.
/// Every page change is logged as host + path only (never query strings or form contents).
@MainActor
final class WebSignInWindow: NSObject {
    private static let size = NSSize(width: 420, height: 780)

    private let callbackScheme: String
    private var window: NSWindow?
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<URL?, Never>?

    init(callbackScheme: String) {
        self.callbackScheme = callbackScheme
    }

    /// Shows the page and returns the callback URL, or nil if the user closed the window.
    func run(url: URL, title: String) async -> URL? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            show(url: url, title: title)
        }
    }

    private func show(url: URL, title: String) {
        let configuration = WKWebViewConfiguration()
        // Fresh, in-memory cookies for every sign-in; nothing is kept afterwards.
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: NSRect(origin: .zero, size: Self.size), configuration: configuration)
        webView.navigationDelegate = self
        self.webView = webView

        let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.size),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = title
        window.contentView = webView
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window

        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        webView.load(URLRequest(url: url))
    }

    private func finish(_ url: URL?) {
        guard let continuation else { return }
        self.continuation = nil
        window?.delegate = nil
        window?.close()
        webView?.navigationDelegate = nil
        webView = nil
        window = nil
        continuation.resume(returning: url)
    }

    private func isCallback(_ url: URL?) -> Bool {
        url?.scheme?.lowercased() == callbackScheme
    }

    private static func describe(_ url: URL?) -> String {
        guard let url else { return "?" }
        return "\(url.scheme ?? "")://\(url.host ?? "")\(url.path)"
    }
}

extension WebSignInWindow: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        let url = navigationAction.request.url
        DiagLog.write("Sign-in page: \(Self.describe(url))")
        guard isCallback(url) else { return decisionHandler(.allow) }
        decisionHandler(.cancel)
        finish(url)
    }

    /// A server redirect to the custom scheme can also end up here as "unsupported URL".
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let failing = (error as NSError).userInfo[NSURLErrorFailingURLErrorKey] as? URL
        if isCallback(failing) { return finish(failing) }
        DiagLog.write("Sign-in page failed: \(Self.describe(failing)) \(error.localizedDescription)")
    }
}

extension WebSignInWindow: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        DiagLog.write("Sign-in window closed by the user")
        finish(nil)
    }
}
