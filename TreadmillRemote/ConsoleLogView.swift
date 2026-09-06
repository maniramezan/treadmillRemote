import SwiftUI

struct ConsoleLogView: View {
    @Bindable var manager: TreadmillManager

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if manager.logs.isEmpty {
                        ContentUnavailableView(
                            "No BLE Traffic",
                            systemImage: "antenna.radiowaves.left.and.right.slash",
                            description: Text("Sent commands and incoming notifications will appear here.")
                        )
                    } else {
                        ForEach(manager.logs) { entry in
                            LogRow(entry: entry)
                                .id(entry.id)
                        }
                    }
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .onChange(of: manager.logs.last?.id) {
                if let id = manager.logs.last?.id {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }
        }
        .navigationTitle("BLE Console")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear", role: .destructive) {
                    manager.clearLogs()
                }
            }
        }
    }
}

private struct LogRow: View {
    let entry: HexLogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(entry.direction.rawValue)
                .font(.caption.weight(.bold).monospaced())
                .foregroundStyle(entry.direction.color)
                .frame(width: 52, alignment: .leading)
            Text(entry.timestamp)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(entry.message)
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.direction.rawValue) \(entry.message) at \(entry.timestamp)")
    }
}

private extension HexLogEntry.Direction {
    var color: Color {
        switch self {
        case .sent:
            .blue
        case .received:
            .green
        case .event:
            .orange
        }
    }
}

