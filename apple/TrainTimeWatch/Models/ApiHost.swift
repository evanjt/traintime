import Foundation

// A user-set API origin, so the apps keep working against a self-hosted
// instance if api.traintime.ch ever goes away. Empty means the built-in host.
// Lives in the shared store because the widget process fetches too.
enum ApiHost {
    static let defaultURL = "https://api.traintime.ch"
    static let key = "apiHost"

    /// Trimmed, trailing slashes dropped. "" for blank input, nil when the
    /// input is not a bare https:// origin (path, query or fragment rejected).
    static func normalise(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") { value.removeLast() }
        if value.isEmpty { return "" }
        guard let components = URLComponents(string: value),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty,
              components.path.isEmpty,
              components.query == nil,
              components.fragment == nil,
              components.user == nil
        else { return nil }
        return value
    }

    static var stored: String {
        get { SharedDefaults.store.string(forKey: key) ?? "" }
        set { SharedDefaults.store.set(newValue, forKey: key) }
    }

    static var baseURL: String {
        let host = stored
        return host.isEmpty ? defaultURL : host
    }
}
