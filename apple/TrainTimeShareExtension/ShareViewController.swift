import UIKit
import UniformTypeIdentifiers

/// Receives an SBB Mobile trip share (URL or plain text), hands the payload
/// to the app via the App Group, then wakes it with traintime://sbbshare.
/// The extension stays dumb: no decoding, no network. The app does both.
class ShareViewController: UIViewController {
    private static let appGroup = "group.com.evanjt.traintime"
    private static let payloadKey = "sbbSharePayload"
    private static let payloadTsKey = "sbbSharePayloadTs"

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task {
            let payload = await collectSharedText()
            if let payload, let defaults = UserDefaults(suiteName: Self.appGroup) {
                defaults.set(payload, forKey: Self.payloadKey)
                defaults.set(Date().timeIntervalSince1970, forKey: Self.payloadTsKey)
            }
            openApp()
            extensionContext?.completeRequest(returningItems: nil)
        }
    }

    /// WhatsApp-style shares arrive as URL items, in-app text shares as
    /// plain text, collect both into one string for the app's link finder.
    private func collectSharedText() async -> String? {
        var parts: [String] = []
        for item in extensionContext?.inputItems.compactMap({ $0 as? NSExtensionItem }) ?? [] {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                    parts.append(url.absoluteString)
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                          let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                    parts.append(text)
                }
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private func openApp() {
        guard let url = URL(string: "traintime://sbbshare") else { return }
        let selector = sel_registerName("openURL:")
        var responder: UIResponder? = self
        while let current = responder {
            if let application = current as? UIApplication {
                application.open(url)
                return
            }
            if current.responds(to: selector) {
                current.perform(selector, with: url)
                return
            }
            responder = current.next
        }
    }
}
