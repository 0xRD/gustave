import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var permission: AccessibilityPermission
    @ObservedObject var scrollInverter: ScrollInverter

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
