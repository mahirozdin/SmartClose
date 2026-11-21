import SwiftUI

struct AppRulesEditorView: View {
    @Binding var rules: [String: AppPolicy]

    @State private var newPattern: String = ""
    @State private var newPolicy: AppPolicy = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Per-App Rules")
                .font(.headline)

            if rules.isEmpty {
                Text("No per-app rules")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(sortedKeys, id: \.self) { key in
                    HStack {
                        Text(key)
                        Spacer()
                        Picker("", selection: binding(for: key)) {
                            ForEach(AppPolicy.allCases) { policy in
                                Text(policy.displayName).tag(policy)
                            }
                        }
                        .frame(width: 220)

                        Button("Remove") {
                            rules.removeValue(forKey: key)
                        }
                        .buttonStyle(.link)
                    }
                }
            }

            Divider()

            HStack {
                TextField("Bundle ID or pattern", text: $newPattern)
                Picker("Policy", selection: $newPolicy) {
                    ForEach(AppPolicy.allCases) { policy in
                        Text(policy.displayName).tag(policy)
                    }
                }
                Button("Add") {
                    let trimmed = newPattern.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    rules[trimmed] = newPolicy
                    requestAutomationIfNeeded(pattern: trimmed, policy: newPolicy)
                    newPattern = ""
                    newPolicy = .default
                }
            }

            Text("“Quit when last document closes” is for apps that keep an empty window open after their last document closes, such as Adobe Illustrator and InDesign. After you close a window, SmartClose asks the app how many documents are open and quits it only when none remain. macOS asks once for permission to control the app (Automation).")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func requestAutomationIfNeeded(pattern: String, policy: AppPolicy) {
        guard policy == .quitWhenLastDocumentCloses else { return }
        AutomationPermission.requestForRunningApps(matching: pattern)
    }

    private var sortedKeys: [String] {
        rules.keys.sorted()
    }

    private func binding(for key: String) -> Binding<AppPolicy> {
        Binding(
            get: { rules[key] ?? .default },
            set: {
                rules[key] = $0
                requestAutomationIfNeeded(pattern: key, policy: $0)
            }
        )
    }
}
