import ApplicationServices

/// An Accessibility element with a short messaging timeout. Every call can block for up to
/// `timeout`, so use it only on one of the `AXQueues`.
struct AXElement: @unchecked Sendable {
    static let timeout: Float = 0.3

    let raw: AXUIElement

    init(_ raw: AXUIElement) {
        self.raw = raw
        AXUIElementSetMessagingTimeout(raw, Self.timeout)
    }

    static func application(_ pid: pid_t) -> AXElement {
        AXElement(AXUIElementCreateApplication(pid))
    }

    /// The raw read, for callers that must tell a timeout from a missing value.
    func copy(_ attribute: String) -> (AXError, CFTypeRef?) {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(raw, attribute as CFString, &value)
        return (error, value)
    }

    func value(_ attribute: String) -> CFTypeRef? {
        let (error, value) = copy(attribute)
        return error == .success ? value : nil
    }

    func string(_ attribute: String) -> String? {
        value(attribute) as? String
    }

    func element(_ attribute: String) -> AXElement? {
        guard let value = value(attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return AXElement(value as! AXUIElement)
    }

    func point(_ attribute: String) -> CGPoint? {
        var point = CGPoint.zero
        return axValue(attribute, type: .cgPoint, into: &point) ? point : nil
    }

    func size(_ attribute: String) -> CGSize? {
        var size = CGSize.zero
        return axValue(attribute, type: .cgSize, into: &size) ? size : nil
    }

    /// Reads several attributes in one round trip. Nil when the app does not answer in time.
    /// A missing attribute comes back as nil in its slot.
    func values(_ attributes: [String]) -> [CFTypeRef?]? {
        var values: CFArray?
        let error = AXUIElementCopyMultipleAttributeValues(
            raw, attributes as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &values)
        guard error == .success, let array = values as [AnyObject]?, array.count == attributes.count
        else { return nil }
        return array.map { value in
            if CFGetTypeID(value) == AXValueGetTypeID(), AXValueGetType(value as! AXValue) == .axError {
                return nil
            }
            return value
        }
    }

    @discardableResult
    func set(_ attribute: String, _ value: CFTypeRef) -> AXError {
        AXUIElementSetAttributeValue(raw, attribute as CFString, value)
    }

    @discardableResult
    func perform(_ action: String) -> AXError {
        AXUIElementPerformAction(raw, action as CFString)
    }

    private func axValue<T: BitwiseCopyable>(_ attribute: String, type: AXValueType, into result: inout T) -> Bool {
        guard let value = value(attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return false }
        return AXValueGetValue(value as! AXValue, type, &result)
    }
}

/// Serial queues for calls into other processes. The Dock gets its own, so a frozen app
/// whose windows are being listed never delays finding the hovered icon. The search for
/// windows on other Spaces gets its own too, so raising a window never waits behind it.
enum AXQueues {
    static let dock = DispatchQueue(label: "io.github.0xrd.gustave.ax.dock", qos: .userInteractive)
    static let windows = DispatchQueue(label: "io.github.0xrd.gustave.ax.windows", qos: .userInitiated)
    static let otherSpaces = DispatchQueue(label: "io.github.0xrd.gustave.ax.other-spaces", qos: .utility)
}
