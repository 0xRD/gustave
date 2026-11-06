import CoreGraphics
import Darwin
import Foundation

/// The private window server functions approved in docs/DECISIONS.md, D26: knowing which
/// Spaces a window is on, and bringing one window forward on any Space. Resolved at run time,
/// so their removal falls back to public behaviour instead of stopping the launch.
enum PrivateWindowServer {
    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias CopySpacesForWindows = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias SetFrontProcessWithOptions = @convention(c) (UnsafeMutableRawPointer, CGWindowID, UInt32) -> CGError
    private typealias PostEventRecordTo = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<UInt8>) -> CGError
    private typealias GetProcessForPID = @convention(c) (pid_t, UnsafeMutableRawPointer) -> OSStatus

    private static let mainConnectionID: MainConnectionID? = symbol("CGSMainConnectionID")
    private static let copySpacesForWindows: CopySpacesForWindows? = symbol("CGSCopySpacesForWindows")
    private static let setFrontProcess: SetFrontProcessWithOptions? = symbol("_SLPSSetFrontProcessWithOptions")
    private static let postEventRecord: PostEventRecordTo? = symbol("SLPSPostEventRecordTo")
    /// Deprecated, but public: the process serial number the two calls above take.
    private static let getProcessForPID: GetProcessForPID? = symbol("GetProcessForPID")

    /// Current, other and user Spaces. Wider masks return nothing for windows on other Spaces.
    private static let allSpacesMask: Int32 = 7
    /// Marks the front process change as made by the user, which lets it switch Spaces.
    private static let userGenerated: UInt32 = 0x200

    static var canReadSpaces: Bool { mainConnectionID != nil && copySpacesForWindows != nil }

    /// Whether the window belongs to at least one Space. A window that belongs to none is
    /// ordered out: a hidden helper window, such as an Electron app's background window.
    /// Nil when this cannot be known, including when the call fails.
    static func isOnSomeSpace(_ windowID: CGWindowID) -> Bool? {
        guard let mainConnectionID, let copySpacesForWindows else { return nil }
        let ids = [NSNumber(value: windowID)] as CFArray
        guard let spaces = copySpacesForWindows(mainConnectionID(), allSpacesMask, ids)?.takeRetainedValue()
        else { return nil }
        return CFArrayGetCount(spaces) > 0
    }

    /// Brings the window forward and makes it key, switching to its Space, even when its app
    /// is already frontmost. Returns false when the functions are missing or refuse, so the
    /// caller can fall back to public calls.
    static func focus(pid: pid_t, windowID: CGWindowID) -> Bool {
        guard let setFrontProcess, let postEventRecord, let getProcessForPID else { return false }
        var psn = [UInt32](repeating: 0, count: 2)
        return psn.withUnsafeMutableBytes { psnBytes -> Bool in
            guard let psnPointer = psnBytes.baseAddress,
                  getProcessForPID(pid, psnPointer) == noErr,
                  setFrontProcess(psnPointer, windowID, userGenerated) == .success
            else { return false }
            makeKey(windowID, psn: psnPointer, postEventRecord: postEventRecord)
            return true
        }
    }

    /// Two synthetic window events, the sequence Hammerspoon, yabai and DockDoor use to make
    /// a window key. Bytes 0x20 to 0x2F are all ones, exactly as they write them: no real
    /// location, so nothing is clicked.
    private static func makeKey(
        _ windowID: CGWindowID,
        psn: UnsafeMutableRawPointer,
        postEventRecord: PostEventRecordTo
    ) {
        var record = [UInt8](repeating: 0, count: 0x100)
        record[0x04] = 0xF8
        record[0x3A] = 0x10
        withUnsafeBytes(of: windowID) { record.replaceSubrange(0x3C..<0x40, with: $0) }
        for index in 0x20..<0x30 {
            record[index] = 0xFF
        }
        for phase: UInt8 in [0x01, 0x02] {
            record[0x08] = phase
            record.withUnsafeMutableBufferPointer { buffer in
                _ = postEventRecord(psn, buffer.baseAddress!)
            }
        }
    }

    private static func symbol<T>(_ name: String) -> T? {
        guard let address = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil }
        return unsafeBitCast(address, to: T.self)
    }
}
