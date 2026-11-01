import SwiftUI

struct SettingsView: View {
    @ObservedObject var permission: AccessibilityPermission

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

            HStack {
                Spacer()
                Button("Quit Gustave") { NSApp.terminate(nil) }
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
