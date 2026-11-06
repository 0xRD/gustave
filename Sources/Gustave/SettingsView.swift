import GustaveCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var permission: AccessibilityPermission
    @ObservedObject var scrollInverter: ScrollInverter
    @ObservedObject var switcher: WindowSwitcher

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: permission.isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(permission.isGranted ? .green : .orange)
                Text(permission.isGranted ? "Accessibility granted" : "Accessibility needed")
                Spacer()
                if !permission.isGranted {
                    Button("Request") { permission.request() }
                    Button("Open Settings") { permission.openSystemSettings() }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Show windows on Dock hover", isOn: $store.settings.dockListEnabled)
                if store.settings.dockListEnabled {
                    HStack {
                        Text("Delay")
                        Slider(value: $store.settings.dockHoverDelay, in: Settings.dockHoverDelayRange, step: 0.1)
                        Text(verbatim: String(format: "%.1f s", store.settings.dockHoverDelay))
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                    .padding(.leading, 20)
                    Picker("Glass", selection: $store.settings.panelGlass) {
                        ForEach(PanelGlass.allCases, id: \.self) { glass in
                            Text(verbatim: glass.label).tag(glass)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.leading, 20)
                }
                Toggle("Option+Tab window switcher", isOn: $store.settings.switcherEnabled)
                if switcher.isUnavailable {
                    Text("Option+Tab is taken by another app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Invert mouse scrolling", isOn: $store.settings.invertMouseScroll)
                Toggle("Invert trackpad scrolling", isOn: $store.settings.invertTrackpadScroll)
                if scrollInverter.isUnavailable {
                    Text("Scroll inversion is unavailable.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!permission.isGranted)

            Divider()

            HStack {
                Spacer()
                Button("Quit Gustave") { NSApp.terminate(nil) }
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
