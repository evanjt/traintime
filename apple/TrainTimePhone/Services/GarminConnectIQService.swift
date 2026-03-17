import Foundation

/// Wraps the Garmin Connect IQ iOS SDK.
/// Requires adding ConnectIQ.framework from the Garmin Developer Portal.
/// If the framework is not linked, all methods gracefully return empty/false.
class GarminConnectIQService {

    static let appUUID = "7df2c0d5-e539-413a-962c-96147dad27f0"

    private var initialized = false

    func initialize() {
        // Load ConnectIQ SDK dynamically to avoid hard crash when framework is missing
        guard let connectIQClass = NSClassFromString("ConnectIQ") else { return }

        let sharedInstance = (connectIQClass as AnyObject).perform(NSSelectorFromString("sharedInstance"))?.takeUnretainedValue()
        guard sharedInstance != nil else { return }
        initialized = true
    }

    func shutdown() {
        initialized = false
    }

    struct GarminDevice {
        let name: String
        let deviceRef: AnyObject  // IQDevice reference
    }

    func getConnectedDevices() -> [GarminDevice] {
        guard initialized else { return [] }

        guard let connectIQClass = NSClassFromString("ConnectIQ"),
              let sharedInstance = (connectIQClass as AnyObject).perform(NSSelectorFromString("sharedInstance"))?.takeUnretainedValue()
        else { return [] }

        guard let devices = sharedInstance.perform(NSSelectorFromString("connectedDevices"))?.takeUnretainedValue() as? [AnyObject]
        else { return [] }

        return devices.compactMap { device in
            let name = device.perform(NSSelectorFromString("friendlyName"))?.takeUnretainedValue() as? String ?? "Garmin Watch"
            return GarminDevice(name: name, deviceRef: device)
        }
    }

    func sendMessage(to device: GarminDevice, data: [String: Any], completion: @escaping (Bool) -> Void) {
        guard initialized else {
            completion(false)
            return
        }

        // The actual Connect IQ SDK calls would be:
        // let app = IQApp(uuid: UUID(uuidString: Self.appUUID)!, store: nil, device: device.deviceRef as! IQDevice)
        // ConnectIQ.sharedInstance().sendMessage(data, to: app) { result in ... }

        // For now, use dynamic dispatch to avoid compile-time dependency
        guard let connectIQClass = NSClassFromString("ConnectIQ"),
              let sharedInstance = (connectIQClass as AnyObject).perform(NSSelectorFromString("sharedInstance"))?.takeUnretainedValue()
        else {
            completion(false)
            return
        }

        // Dynamic invocation of sendMessage — this is a simplified bridge
        // Real integration should import the ConnectIQ framework directly
        _ = sharedInstance
        completion(false)  // Placeholder until framework is linked
    }
}
