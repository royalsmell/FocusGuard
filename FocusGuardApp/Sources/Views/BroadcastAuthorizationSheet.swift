import SharedCore
import SwiftUI

struct BroadcastAuthorizationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @State private var appearedAt = Date()
    @State private var now = Date()

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image(systemName: isConnected ? "checkmark.circle.fill" : "rectangle.on.rectangle.circle")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(isConnected ? .green : .indigo)

                VStack(spacing: 8) {
                    Text(isConnected ? "屏幕共享已连接" : "开启 AI 屏幕共享")
                        .font(.title2.bold())
                    Text(isConnected
                         ? "现在可以离开专注守望，AI 会在屏幕广播期间继续评估画面。"
                         : "请点下面的系统广播按钮，再在系统窗口中点“开始广播”。")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if isConnected {
                    Label("专注守望屏幕分析正在接收画面", systemImage: "wave.3.right.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(.green.opacity(0.1), in: Capsule())
                } else {
                    VStack(spacing: 10) {
                        BroadcastPickerButton(
                            preferredExtension: nil
                        )
                        Text("系统列表出现后，请选择“专注守望屏幕分析”。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 420)

                    VStack(alignment: .leading, spacing: 10) {
                        instructionRow(number: 1, text: "点上方“授权屏幕共享”按钮")
                        instructionRow(number: 2, text: "在系统窗口中确认“专注守望屏幕分析”")
                        instructionRow(number: 3, text: "点“开始广播”，等待 3 秒倒计时")
                    }
                    .frame(maxWidth: 420)

                    Label("控制中心里的普通“屏幕录制”不会把画面交给本 App。必须从这里开启专注守望的广播扩展。", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(12)
                        .background(.secondary.opacity(0.08), in: .rect(cornerRadius: 12))

                    if now.timeIntervalSince(appearedAt) >= 15 {
                        Text("还没有检测到连接。请确认系统窗口里选择的是“专注守望屏幕分析”，而不是“照片”或普通屏幕录制。")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                    }
                }

                if isConnected {
                    Button("完成") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .tint(.indigo)
                } else {
                    Button("稍后开启") { dismiss() }
                        .buttonStyle(.bordered)
                        .tint(.indigo)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(24)
        }
        .navigationTitle("屏幕共享")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(false)
        .task {
            appearedAt = Date()
            while !Task.isCancelled, model.activeSession != nil {
                now = Date()
                await model.refreshActiveSession()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var isConnected: Bool {
        guard let session = model.activeSession,
              let latest = session.events
                .filter({ $0.source == .broadcast && $0.broadcastState != nil })
                .max(by: { $0.timestamp < $1.timestamp }) else {
            return false
        }
        return latest.broadcastState == .started || latest.broadcastState == .resumed
    }

    private func instructionRow(number: Int, text: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(.indigo, in: Circle())
            Text(text)
                .font(.subheadline)
            Spacer(minLength: 0)
        }
    }
}

#Preview {
    NavigationStack {
        BroadcastAuthorizationSheet()
    }
    .environment(AppModel())
}
