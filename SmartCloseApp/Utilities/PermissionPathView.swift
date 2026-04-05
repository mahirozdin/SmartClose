import AppKit
import SwiftUI

struct PermissionPathView: View {
    private let appPath = Bundle.main.bundleURL.path

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("App Path")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(appPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Button("Copy App Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(appPath, forType: .string)
                Log.permissions.info("Copied app path")
            }
            .font(.caption)
        }
        .padding(.top, 4)
    }
}
