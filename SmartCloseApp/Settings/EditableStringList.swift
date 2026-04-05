import SwiftUI

struct EditableStringList: View {
    let title: String
    let placeholder: String
    @Binding var items: [String]

    @State private var newItem: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            if items.isEmpty {
                Text("None")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(items, id: \.self) { item in
                    HStack {
                        Text(item)
                        Spacer()
                        Button("Remove") {
                            items.removeAll { $0 == item }
                        }
                        .buttonStyle(.link)
                    }
                }
            }

            HStack {
                TextField(placeholder, text: $newItem)
                Button("Add") {
                    let trimmed = newItem.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    items.append(trimmed)
                    newItem = ""
                }
            }
        }
    }
}
