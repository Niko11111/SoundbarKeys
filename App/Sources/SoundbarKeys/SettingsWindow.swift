import AppKit
import SwiftUI

/// Settings window with toolbar tabs (like Safari or Mail). Each tab lives in its own file
/// (`Settings<Name>Tab.swift`); new settings go into the matching tab, a new area gets a new tab.
@MainActor
final class SettingsWindowController {
    /// Tabs in toolbar order.
    enum Tab: Int {
        case general, volume, soundbar, account, about
    }

    private var window: NSWindow?
    private let model: AppModel
    private let actions: PanelActions

    init(model: AppModel, actions: PanelActions) {
        self.model = model
        self.actions = actions
    }

    func show(tab: Tab? = nil) {
        if window == nil { window = makeWindow() }
        if let tab, let tabs = window?.contentViewController as? NSTabViewController {
            tabs.selectedTabViewItemIndex = tab.rawValue
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        let settings = Settings.shared
        add(SettingsGeneralTab(model: model, settings: settings, actions: actions),
            title: String(localized: "General"), symbol: "gearshape", to: tabs)
        add(SettingsVolumeTab(model: model, settings: settings),
            title: String(localized: "Volume"), symbol: "speaker.wave.2", to: tabs)
        add(SettingsSoundbarTab(model: model, settings: settings, actions: actions),
            title: String(localized: "Soundbar"), symbol: "hifispeaker", to: tabs)
        add(SettingsAccountTab(model: model, actions: actions),
            title: String(localized: "Account"), symbol: "person.crop.circle", to: tabs)
        add(SettingsAboutTab(), title: String(localized: "About"), symbol: "info.circle", to: tabs)

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func add(_ page: some View, title: String, symbol: String, to tabs: NSTabViewController) {
        let controller = SettingsPageController(rootView: AnyView(page))
        controller.title = title
        let item = NSTabViewItem(viewController: controller)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        tabs.addTabViewItem(item)
    }
}

/// Hosts one tab. Reports the page's natural height to the tab controller (which sizes the window
/// to it), but never more than fits on the screen; the page scrolls beyond that.
private final class SettingsPageController: NSHostingController<AnyView> {
    /// Room left for the title bar, the toolbar and a margin.
    private static let screenMargin: CGFloat = 160

    override init(rootView: AnyView) {
        super.init(rootView: rootView)
        sizingOptions = [.preferredContentSize]
    }

    @MainActor required dynamic init?(coder: NSCoder) {
        fatalError("not used")
    }

    override var preferredContentSize: NSSize {
        get {
            let natural = super.preferredContentSize
            let available = (NSScreen.main?.visibleFrame.height ?? natural.height) - Self.screenMargin
            return NSSize(width: natural.width, height: min(natural.height, available))
        }
        set { super.preferredContentSize = newValue }
    }
}

/// Frame of a settings tab: a grouped form, scrollable when it is taller than the window.
struct SettingsPage<Content: View>: View {
    static var width: CGFloat { 480 }

    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            Form { content }
                .formStyle(.grouped)
                .scrollDisabled(true)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: Self.width)
    }
}
