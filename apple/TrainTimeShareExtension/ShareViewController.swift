import UIKit
import Social
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // Open the main app via URL scheme, then complete the extension
        if let url = URL(string: "traintime://sbbshare") {
            // Use openURL via UIApplication (shared extension context)
            var responder: UIResponder? = self
            while responder != nil {
                if let application = responder as? UIApplication {
                    application.open(url)
                    break
                }
                responder = responder?.next
            }

            // On iOS 16+, use the responder chain to open URL
            let selector = sel_registerName("openURL:")
            responder = self
            while responder != nil {
                if responder!.responds(to: selector) {
                    responder!.perform(selector, with: url)
                    break
                }
                responder = responder?.next
            }
        }

        extensionContext?.completeRequest(returningItems: nil)
    }
}
