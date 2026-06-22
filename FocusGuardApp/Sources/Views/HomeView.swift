import SharedCore
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var goal = ""
    @State private var durationHours = 0
    @State private var durationMinutes = 25
    @State private var rewritePreview: GoalRewritePreview?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let session = model.activeSession {
                    ActiveSessionCard(session: session)
                } else {
                    newSessionContent
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("专注守望")
        .toolbar {
            if model.isBusy {
                ToolbarItem(placement: .topBarTrailing) { ProgressView() }
            }
        }
        .sheet(item: $rewritePreview) { preview in
            GoalRewritePreviewView(preview: preview) {
                goal = preview.result.rewrittenGoal
                rewritePreview = nil
            } onCancel: {
                rewritePreview = nil
            }
        }
    }

    private var newSessionContent: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Label("这次要完成什么？", systemImage: "text.cursor")
                    .font(.headline)
                TextField("例如：完成产品需求文档第一稿", text: $goal, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                    .accessibilityIdentifier("goal-field")
                HStack {
                    Spacer()
                    Button {
                        let original = goal
                        Task {
                            if let result = await model.rewriteGoal(original) {
                                rewritePreview = GoalRewritePreview(original: original, result: result)
                            }
                        }
                    } label: {
                        Label("AI 改写", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isBusy || goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .focusCard()

            VStack(alignment: .leading, spacing: 12) {
                Label("专注时长", systemImage: "timer")
                    .font(.headline)

                HStack(spacing: 8) {
                    ForEach(model.durationPreferences.quickMinutes.indices, id: \.self) { index in
                        let quickMinutes = model.durationPreferences.quickMinutes[index]
                        Button(FocusDurationText.compact(minutes: quickMinutes)) {
                            setDuration(totalMinutes: quickMinutes)
                        }
                        .buttonStyle(DurationButtonStyle(selected: totalMinutes == quickMinutes))
                        .accessibilityLabel(FocusDurationText.full(minutes: quickMinutes))
                    }
                }
                .frame(maxWidth: .infinity)

                Divider()
                DurationWheelPicker(hours: $durationHours, minutes: $durationMinutes)
            }
            .focusCard()

            Button {
                Task {
                    let previousSessionID = model.activeSession?.id
                    await model.startSession(goal: goal, durationMinutes: totalMinutes)
                    if let session = model.activeSession, session.id != previousSessionID {
                        router.presentedSheet = .broadcastAuthorization
                    }
                }
            } label: {
                Label("开始 \(FocusDurationText.full(minutes: totalMinutes))", systemImage: "scope")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
            .disabled(
                model.isBusy
                    || totalMinutes < DurationPreferences.allowedMinutes.lowerBound
                    || goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
            .accessibilityIdentifier("start-session")
        }
    }

    private var totalMinutes: Int {
        FocusDuration.totalMinutes(hours: durationHours, minutes: durationMinutes)
    }

    private func setDuration(totalMinutes: Int) {
        let components = FocusDuration.components(totalMinutes: totalMinutes)
        durationHours = components.hours
        durationMinutes = components.minutes
    }
}

private struct GoalRewritePreview: Identifiable {
    let id = UUID()
    let original: String
    let result: GoalRewriteResult
}

private struct GoalRewritePreviewView: View {
    let preview: GoalRewritePreview
    let onUse: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("原目标") { Text(preview.original) }
                Section("AI 改写") { Text(preview.result.rewrittenGoal).font(.headline) }
                Section("改写理由") { Text(preview.result.reason).foregroundStyle(.secondary) }
            }
            .navigationTitle("确认任务改写")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) { Button("使用改写", action: onUse).bold() }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct ActiveSessionCard: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    let session: FocusSession

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "scope")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.indigo)
            Text(session.goal)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(remainingText(at: context.date))
                    .font(.system(size: 54, weight: .semibold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.65)
            }

            VStack(spacing: 10) {
                BroadcastPickerView(preferredExtension: nil)
                    .frame(width: 54, height: 54)
                    .accessibilityLabel("开启或停止 AI 屏幕广播")
                Text("点按上方系统按钮开启屏幕广播")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("打开屏幕共享引导") {
                    router.presentedSheet = .broadcastAuthorization
                }
                .font(.footnote.bold())
                BroadcastHealthView(session: session)
            }

            if let latest = session.events.last(where: { $0.source == .visionAI }) {
                StatusPill(level: latest.level, text: latest.reason)
            }

            Button("提前结束", role: .destructive) {
                Task { await model.stopSession() }
            }
            .buttonStyle(.bordered)
            .disabled(model.isBusy)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .focusCard()
    }

    private func remainingText(at date: Date) -> String {
        FocusDurationText.countdown(seconds: Int(session.plannedEnd.timeIntervalSince(date)))
    }
}

private struct BroadcastHealthView: View {
    let session: FocusSession

    var body: some View {
        Label(status.text, systemImage: status.icon)
            .font(.footnote.bold())
            .foregroundStyle(status.color)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(status.color.opacity(0.1), in: Capsule())
    }

    private var status: (text: String, icon: String, color: Color) {
        let broadcastEvents = session.events.filter { $0.source == .broadcast }
        if let latest = broadcastEvents.last, latest.broadcastState == .stopped {
            return (String(localized: "广播已停止"), "record.circle", .orange)
        }
        if let latestVision = session.events.last(where: { $0.source == .visionAI }),
           Date().timeIntervalSince(latestVision.timestamp) < 90 {
            return (String(localized: "AI 正在观测"), "eye.fill", .green)
        }
        if broadcastEvents.contains(where: { $0.broadcastState == .started || $0.broadcastState == .resumed }) {
            return (String(localized: "广播已连接 · 等待下一帧"), "wave.3.right", .indigo)
        }
        return (String(localized: "等待开启屏幕广播"), "record.circle", .secondary)
    }
}

private struct DurationButtonStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.bold())
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(selected ? Color.indigo : Color.secondary.opacity(0.1), in: .rect(cornerRadius: 12))
            .foregroundStyle(selected ? .white : .primary)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
