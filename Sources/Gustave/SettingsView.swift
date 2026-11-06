import GustaveCore
import SwiftUI

/// The settings window, in Hector's family: warm canvas, cards, a serif title and the mark.
/// Every feature is one switch, and says in a line what it does.
struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var permission: AccessibilityPermission
    @ObservedObject var scrollInverter: ScrollInverter
    @ObservedObject var switcher: WindowSwitcher
    @ObservedObject var launchAtLogin: LaunchAtLogin

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            header
            permissionCard
            featuresCard
                .disabled(!permission.isGranted)
            generalCard
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.xl + Spacing.md)
        .padding(.bottom, Spacing.xl)
        .frame(width: 460)
        .background(Color.surfaceCanvas)
    }

    private var header: some View {
        HStack(spacing: Spacing.md) {
            GustaveMark()
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text("Gustave")
                    .font(.system(size: 24, weight: .semibold, design: .serif))
                Text("Hector's neighbour. Windows and scrolling, offline.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var permissionCard: some View {
        Card {
            HStack(alignment: .top, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Accessibility")
                        .font(.headline)
                    Text(permission.isGranted
                         ? "Gustave can see and arrange windows. It needs nothing else."
                         : "Gustave needs it to list windows and invert scrolling. Nothing else is asked for.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Spacing.sm)
                StatusPill(isOK: permission.isGranted, text: permission.isGranted ? "Allowed" : "Needed")
            }
            if !permission.isGranted {
                HStack {
                    Spacer()
                    Button("Open Settings") { permission.openSystemSettings() }
                    Button("Allow Access") { permission.request() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private var featuresCard: some View {
        Card {
            SettingToggle(
                title: "Window list on Dock hover",
                detail: "Rest the pointer on an app in the Dock to see its windows.",
                isOn: $store.settings.dockListEnabled
            )
            if store.settings.dockListEnabled {
                HStack(spacing: Spacing.sm) {
                    Text("Delay")
                        .font(.callout)
                    Slider(value: $store.settings.dockHoverDelay, in: Settings.dockHoverDelayRange, step: 0.1)
                    Text(verbatim: String(format: "%.1f s", store.settings.dockHoverDelay))
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
                .padding(.leading, Spacing.lg)
            }
            Divider()
            SettingToggle(
                title: "Option+Tab window switcher",
                detail: "Every window, most recent first. A quick press goes back to the last one.",
                isOn: $store.settings.switcherEnabled
            )
            if switcher.isUnavailable {
                Note("Option+Tab is taken by another app.")
            }
            Divider()
            SettingToggle(
                title: "Invert mouse scrolling",
                detail: "For a wheel mouse.",
                isOn: $store.settings.invertMouseScroll
            )
            SettingToggle(
                title: "Invert trackpad scrolling",
                detail: "For a trackpad or a Magic Mouse.",
                isOn: $store.settings.invertTrackpadScroll
            )
            if scrollInverter.isUnavailable {
                Note("Scroll inversion is unavailable.")
            }
        }
    }

    private var generalCard: some View {
        Card {
            SettingToggle(
                title: "Open at login",
                detail: "Gustave starts quietly when you log in.",
                isOn: Binding(get: { launchAtLogin.isEnabled }, set: { launchAtLogin.set($0) })
            )
            if launchAtLogin.needsApproval {
                HStack {
                    Note("Allow Gustave in System Settings, Login Items.")
                    Spacer()
                    Button("Open Login Items") { launchAtLogin.openLoginItems() }
                }
            }
            if launchAtLogin.failed {
                Note("This could not be changed. Try again from the app in Applications.")
            }
            Divider()
            HStack {
                Text("Offline, no tracking, Accessibility only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Quit Gustave") { NSApp.terminate(nil) }
            }
        }
    }
}

/// A group of related settings on a card, as in Hector.
private struct Card<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            content()
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.surfaceStroke))
    }
}

private struct SettingToggle: View {
    let title: String
    let detail: String
    let isOn: Binding<Bool>

    var body: some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
    }
}

/// Hector's verdict pill: a colour and a shape, never colour alone.
private struct StatusPill: View {
    let isOK: Bool
    let text: String

    var body: some View {
        Label(text, systemImage: isOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(isOK ? Color.gustaveOK : Color.gustaveWarning)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 3)
            .background(isOK ? Color.gustaveOKWash : Color.gustaveWarningWash, in: Capsule())
    }
}

private struct Note: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
