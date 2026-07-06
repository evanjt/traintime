import Foundation
#if canImport(ConnectIQ)
import ConnectIQ
#endif

/// Bridges the phone to a Garmin watch over the Connect IQ Mobile SDK, relayed via the
/// Garmin Connect Mobile app. This is the cross-ecosystem analog of WCSession.
///
/// The whole feature is optional. The real SDK code compiles only when
/// `ConnectIQ.xcframework` is linked (download it from the Garmin developer portal and add
/// it to the TrainTimePhone target). Without the framework the `#else` stub keeps the app
/// building and every entry point becomes a silent no-op, so users with no Garmin watch,
/// or no Garmin Connect app, are unaffected.
final class GarminConnectIQService: NSObject {

    static let appUUID = "7df2c0d5-e539-413a-962c-96147dad27f0"
    /// Must match the CFBundleURLSchemes entry in Info.plist. Garmin Connect bounces the
    /// device-selection result back to the app through this scheme.
    static let urlScheme = "traintime-ciq"

    struct GarminDevice {
        let id: String       // IQDevice.uuid as a string, stable across launches
        let name: String
    }

    /// Invoked on the main queue when the watch sends state back (defaultMode via PhoneSync
    /// on the Garmin side). Shape matches WCSession's application context.
    var onMessageReceived: (([String: Any]) -> Void)?

    /// Fires when a watch connects/disconnects (e.g. Bluetooth toggled), for live status.
    var onLinkChanged: (() -> Void)?

    #if canImport(ConnectIQ)

    /// The Connect IQ SDK is linked, so pairing UI can be offered.
    let isAvailable = true

    private var devices: [IQDevice] = []
    private var apps: [UUID: IQApp] = [:]
    private var statuses: [UUID: IQDeviceStatus] = [:]
    private let defaultsKey = "garminKnownDevices"

    func initialize() {
        ConnectIQ.sharedInstance().initialize(withUrlScheme: Self.urlScheme, uiOverrideDelegate: self)
        restoreDevices()
        registerAll()
    }

    func shutdown() {
        for device in devices {
            ConnectIQ.sharedInstance().unregister(forDeviceEvents: device, delegate: self)
            if let app = apps[device.uuid] {
                ConnectIQ.sharedInstance().unregister(forAppMessages: app, delegate: self)
            }
        }
    }

    /// Opens Garmin Connect so the user can pick which paired watch(es) to use. The result
    /// returns asynchronously through `handleOpenURL`.
    func showDeviceSelection() {
        ConnectIQ.sharedInstance().showDeviceSelection()
    }

    /// Call from the app's `.onOpenURL`. Returns true if the URL was a Connect IQ callback.
    @discardableResult
    func handleOpenURL(_ url: URL) -> Bool {
        guard url.scheme == Self.urlScheme else { return false }
        guard let selected = ConnectIQ.sharedInstance().parseDeviceSelectionResponse(from: url) as? [IQDevice] else {
            return true
        }
        shutdown()
        devices = selected
        apps.removeAll()
        statuses.removeAll()
        saveDevices()
        registerAll()
        return true
    }

    /// True when at least one known Garmin watch exists, so the UI can offer pairing /
    /// hide the option entirely. (A device can be known but not currently connected.)
    var hasKnownDevices: Bool { !devices.isEmpty }

    func getConnectedDevices() -> [GarminDevice] {
        devices
            .filter { statuses[$0.uuid] == .connected }
            .map { GarminDevice(id: $0.uuid?.uuidString ?? "", name: $0.friendlyName ?? "Garmin Watch") }
    }

    func sendMessage(to device: GarminDevice, data: [String: Any], completion: @escaping (Bool) -> Void) {
        guard let uuid = UUID(uuidString: device.id), let app = apps[uuid] else {
            completion(false)
            return
        }
        ConnectIQ.sharedInstance().sendMessage(data, to: app, progress: nil) { result in
            DispatchQueue.main.async { completion(result == .success) }
        }
    }

    /// Asks the watch to launch TrainTime, the one place we legitimately wake the watch,
    /// because the user tapped the indicator. Best-effort over BLE; a no-op when already
    /// running. The Garmin peer of `openApp` on Android. (Apple Watch has no equivalent:
    /// the iPhone cannot launch its watchOS app.)
    func openApplication(on device: GarminDevice) {
        guard let uuid = UUID(uuidString: device.id), let app = apps[uuid] else { return }
        ConnectIQ.sharedInstance().openAppRequest(app) { _ in }
    }

    // MARK: - Device registration + persistence

    private func registerAll() {
        guard let appUUID = UUID(uuidString: Self.appUUID) else { return }
        for device in devices {
            guard let deviceUUID = device.uuid else { continue }
            ConnectIQ.sharedInstance().register(forDeviceEvents: device, delegate: self)
            if let app = IQApp(uuid: appUUID, store: UUID(), device: device) {
                apps[deviceUUID] = app
                ConnectIQ.sharedInstance().register(forAppMessages: app, delegate: self)
            }
        }
    }

    private func saveDevices() {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: devices, requiringSecureCoding: true) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private func restoreDevices() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let restored = try? NSKeyedUnarchiver.unarchivedArrayOfObjects(ofClass: IQDevice.self, from: data) else {
            return
        }
        devices = restored
    }

    #else

    // Graceful stub. ConnectIQ.xcframework not linked. Garmin never appears in the UI.
    let isAvailable = false
    func initialize() {}
    func shutdown() {}
    func showDeviceSelection() {}
    @discardableResult func handleOpenURL(_ url: URL) -> Bool { false }
    var hasKnownDevices: Bool { false }
    func getConnectedDevices() -> [GarminDevice] { [] }
    func sendMessage(to device: GarminDevice, data: [String: Any], completion: @escaping (Bool) -> Void) {
        completion(false)
    }
    func openApplication(on device: GarminDevice) {}

    #endif
}

#if canImport(ConnectIQ)
extension GarminConnectIQService: IQDeviceEventDelegate, IQAppMessageDelegate, IQUIOverrideDelegate {

    func deviceStatusChanged(_ device: IQDevice, status: IQDeviceStatus) {
        guard let uuid = device.uuid else { return }
        statuses[uuid] = status
        DispatchQueue.main.async { self.onLinkChanged?() }
    }

    func receivedMessage(_ message: Any, from app: IQApp) {
        guard let dict = message as? [String: Any] else { return }
        DispatchQueue.main.async { self.onMessageReceived?(dict) }
    }

    // Garmin Connect Mobile isn't installed. The link can't work. Stay silent; the UI
    // simply never lists a Garmin watch.
    func needsToInstallConnectMobile() {}
}
#endif
