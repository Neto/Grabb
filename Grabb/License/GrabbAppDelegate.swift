import AppKit

/// Owns the license and receives grabb://activate?key=… links.
/// The link is caught as an Apple Event before SwiftUI sees it, so SwiftUI
/// does not open a second window for it.
@MainActor
final class GrabbAppDelegate: NSObject, NSApplicationDelegate {
    let license = SpoonLicense(
        product: "grabb",
        displayName: "Grabb",
        buyURL: URL(string: "https://buy.stripe.com/eVqcN4bgo7CecMt1rR3AY01")!
    )

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let text = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: text) else { return }
        license.handle(url: url)
        NSApp.activate()
    }
}
