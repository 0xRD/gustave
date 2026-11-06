import ApplicationServices
import Darwin

/// The private Accessibility functions approved in docs/DECISIONS.md, D17. Resolved at run
/// time so their removal turns off windows on other Spaces instead of stopping the launch.
enum PrivateAccessibility {
    private typealias CreateWithRemoteToken = @convention(c) (CFData) -> Unmanaged<AXUIElement>?
    private typealias GetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    private static let createWithRemoteToken: CreateWithRemoteToken? =
        symbol("_AXUIElementCreateWithRemoteToken", as: CreateWithRemoteToken.self)
    private static let getWindow: GetWindow? = symbol("_AXUIElementGetWindow", as: GetWindow.self)

    static var isAvailable: Bool { createWithRemoteToken != nil && getWindow != nil }

    static func windowID(of element: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        guard let getWindow, getWindow(element, &id) == .success, id != 0 else { return nil }
        return id
    }

    /// The element with `elementID` in the app, if it exists. The token layout is pid, zero,
    /// the 'coco' tag and the element id.
    static func element(pid: pid_t, elementID: UInt64) -> AXUIElement? {
        guard let createWithRemoteToken else { return nil }
        var token = Data(count: 20)
        token.withUnsafeMutableBytes { bytes in
            bytes.storeBytes(of: pid, toByteOffset: 0, as: Int32.self)
            bytes.storeBytes(of: 0, toByteOffset: 4, as: Int32.self)
            bytes.storeBytes(of: 0x636F_636F, toByteOffset: 8, as: Int32.self)
            bytes.storeBytes(of: elementID, toByteOffset: 12, as: UInt64.self)
        }
        return createWithRemoteToken(token as CFData)?.takeRetainedValue()
    }

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let address = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil }
        return unsafeBitCast(address, to: type)
    }
}
