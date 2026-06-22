import SwiftUI

struct OnboardingView: View {
    @State private var page = 0
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: pageIcon)
                .font(.system(size: 62, weight: .semibold))
                .foregroundStyle(.indigo)
                .contentTransition(.symbolEffect(.replace))
            Text(pageTitle)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text(pageBody)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Spacer()
            HStack(spacing: 7) {
                ForEach(0..<2) { index in
                    Capsule()
                        .fill(index == page ? Color.indigo : Color.secondary.opacity(0.25))
                        .frame(width: index == page ? 24 : 8, height: 8)
                }
            }
            Button {
                advance()
            } label: {
                Text(page == 1 ? "开始使用" : "继续")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
            .padding(.horizontal, 24)
        }
        .padding(.vertical, 32)
        .background(Color(.systemGroupedBackground))
    }

    private func advance() {
        if page == 0 {
            withAnimation { page = 1 }
        } else {
            onComplete()
        }
    }

    private var pageIcon: String {
        ["scope", "record.circle"][page]
    }

    private var pageTitle: String {
        [
            String(localized: "守住真正重要的事"),
            String(localized: "AI 屏幕守望由你开启")
        ][page]
    }

    private var pageBody: String {
        [
            String(localized: "写下一个目标，选择一段时间，然后只管开始。"),
            String(localized: "开始专注后，请确认系统屏幕广播。原始画面不会保存，只保留确认分心事件的缩略图。")
        ][page]
    }
}
