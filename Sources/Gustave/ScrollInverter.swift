import ApplicationServices
import Combine
import CoreGraphics
import GustaveCore

/// Owns the only event tap in the app. The tap exists only while inversion is wanted and
/// permitted, and it sees nothing but scroll-wheel events.
@MainActor
final class ScrollInverter: ObservableObject {
    /// True when inversion is wanted but the system refused the tap.
    @Published private(set) var isUnavailable = false

    private var settings = Settings()
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    func update(settings: Settings, isPermissionGranted: Bool) {
        self.settings = settings
        if ScrollRule.needsEventTap(settings) && isPermissionGranted {
            install()
        } else {
            remove()
        }
    }

    private func install() {
        guard tap == nil else { return }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1) << CGEventType.scrollWheel.rawValue,
            callback: scrollTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            isUnavailable = true
            return
        }
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port
        runLoopSource = source
        isUnavailable = false
    }

    private func remove() {
        isUnavailable = false
        guard let port = tap else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CFMachPortInvalidate(port)
        tap = nil
        runLoopSource = nil
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .scrollWheel:
            invertIfNeeded(event)
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            recoverTap()
        default:
            break
        }
    }

    private func invertIfNeeded(_ event: CGEvent) {
        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        guard ScrollRule.shouldInvert(ScrollDevice(isContinuous: isContinuous), settings: settings)
        else { return }

        // Read everything first: setting one delta can change the others.
        let delta = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let fixedPointDelta = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        let pointDelta = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)

        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: ScrollRule.inverted(delta))
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -fixedPointDelta)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: ScrollRule.inverted(pointDelta))
    }

    private func recoverTap() {
        guard let port = tap else { return }
        // A disable can mean the permission was revoked. Never keep a tap in that state.
        if AXIsProcessTrusted() {
            CGEvent.tapEnable(tap: port, enable: true)
        } else {
            remove()
        }
    }
}

private let scrollTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    if let userInfo {
        // The run loop source is on the main run loop, so this runs on the main thread.
        let inverter = Unmanaged<ScrollInverter>.fromOpaque(userInfo).takeUnretainedValue()
        MainActor.assumeIsolated {
            inverter.handle(type: type, event: event)
        }
    }
    return Unmanaged.passUnretained(event)
}
