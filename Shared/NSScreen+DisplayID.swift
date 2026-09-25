import AppKit

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    static func withDisplayID(_ id: CGDirectDisplayID) -> NSScreen? {
        screens.first { $0.displayID == id }
    }
}
