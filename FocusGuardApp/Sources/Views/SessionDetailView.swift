import SharedCore
import SwiftUI

struct SessionDetailView: View {
    let session: FocusSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(session.goal)
                        .font(.title2.bold())
                    Text(session.plannedStart.formatted(date: .long, time: .shortened))
                        .foregroundStyle(.secondary)
                    MetricBar(breakdown: session.breakdown)
                        .frame(height: 12)
                    HStack {
                        MetricLegend(color: .green, title: String(localized: "专注"), seconds: session.breakdown.focusedSeconds)
                        MetricLegend(color: .orange, title: String(localized: "走神"), seconds: session.breakdown.wanderingSeconds)
                        MetricLegend(color: .red, title: String(localized: "分心"), seconds: session.breakdown.distractedSeconds)
                        MetricLegend(color: .gray, title: String(localized: "未观测"), seconds: session.breakdown.unknownSeconds)
                    }
                    Text("观测覆盖率 \(Int((session.breakdown.coverage * 100).rounded()))%")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .focusCard()

                if let summary = session.summary {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("本次复盘", systemImage: "sparkles")
                            .font(.headline)
                        Text(summary)
                            .font(.body)
                            .textSelection(.enabled)
                    }
                    .focusCard()
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("时间线")
                        .font(.headline)
                    let events = session.events.filter { $0.source == .visionAI }
                    if events.isEmpty {
                        Text("本次没有可展示的观测事件。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(events) { event in
                            EventRow(event: event)
                            if event.id != events.last?.id { Divider() }
                        }
                    }
                }
                .focusCard()
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("专注详情")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MetricBar: View {
    let breakdown: FocusBreakdown

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                segment(.green, seconds: breakdown.focusedSeconds, width: proxy.size.width)
                segment(.orange, seconds: breakdown.wanderingSeconds, width: proxy.size.width)
                segment(.red, seconds: breakdown.distractedSeconds, width: proxy.size.width)
                segment(.gray.opacity(0.5), seconds: breakdown.unknownSeconds, width: proxy.size.width)
            }
            .clipShape(Capsule())
        }
    }

    private func segment(_ color: Color, seconds: TimeInterval, width: CGFloat) -> some View {
        color.frame(width: breakdown.totalSeconds > 0 ? width * seconds / breakdown.totalSeconds : 0)
    }
}

private struct MetricLegend: View {
    let color: Color
    let title: String
    let seconds: TimeInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(title)
            }
            Text("\(Int(seconds / 60))m")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct EventRow: View {
    let event: FocusEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let relativePath = event.thumbnailRelativePath,
               let image = UIImage(contentsOfFile: SharedEnvironment.containerURL().appendingPathComponent(relativePath).path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 68, height: 48)
                    .clipShape(.rect(cornerRadius: 8))
            } else {
                Image(systemName: "eye")
                    .frame(width: 32, height: 32)
                    .foregroundStyle(event.level == .distracted ? .red : .secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(event.level.displayName).font(.subheadline.bold())
                    Spacer()
                    Text(event.timestamp.formatted(date: .omitted, time: .standard))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(event.reason.isEmpty ? String(localized: "没有补充说明") : event.reason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
