import SharedCore
import SwiftUI

extension View {
    func focusCard() -> some View {
        self
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.primary.opacity(0.06))
            }
    }
}

struct StatusPill: View {
    let level: FocusLevel
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(level.displayName).font(.subheadline.bold())
                if !text.isEmpty {
                    Text(text).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(color.opacity(0.1), in: .rect(cornerRadius: 14))
    }

    private var color: Color {
        switch level {
        case .focused: .green
        case .wandering: .orange
        case .distracted: .red
        case .unknown: .gray
        }
    }
}
