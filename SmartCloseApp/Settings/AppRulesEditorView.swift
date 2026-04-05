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
                    newPattern = ""
                    newPolicy = .default
                }
            }
        }
    }

    private var sortedKeys: [String] {
        rules.keys.sorted()
    }

    private func binding(for key: String) -> Binding<AppPolicy> {
        Binding(
            get: { rules[key] ?? .default },
            set: { rules[key] = $0 }
        )
    }
}
