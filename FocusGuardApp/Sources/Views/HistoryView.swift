import Charts
import SharedCore
import SwiftUI

struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var page = HistoryPage.records

    var body: some View {
        VStack(spacing: 0) {
            Picker("历史页面", selection: $page) {
                Text("记录").tag(HistoryPage.records)
                Text("统计").tag(HistoryPage.analytics)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            switch page {
            case .records: recordsView
            case .analytics: HistoryAnalyticsView(sessions: completedSessions)
            }
        }
        .navigationTitle("专注历史")
        .navigationDestination(for: UUID.self) { id in
            if let session = model.session(with: id) { SessionDetailView(session: session) }
        }
    }

    @ViewBuilder
    private var recordsView: some View {
        if completedSessions.isEmpty {
            ContentUnavailableView(
                "还没有专注记录",
                systemImage: "clock.arrow.circlepath",
                description: Text("完成第一场专注后，复盘会出现在这里。")
            )
        } else {
            List(completedSessions) { session in
                NavigationLink(value: session.id) { SessionRow(session: session) }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("删除", role: .destructive) {
                            Task { await model.deleteSession(id: session.id) }
                        }
                    }
            }
            .listStyle(.insetGrouped)
        }
    }

    private var completedSessions: [FocusSession] {
        model.sessions.filter { $0.status != .active }
    }
}

private enum HistoryPage { case records, analytics }

private struct HistoryAnalyticsView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let sessions: [FocusSession]
    @State private var scope = AnalyticsScope.session

    private var report: AnalyticsReport { FocusAnalytics.report(sessions: sessions, scope: scope) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Picker("统计周期", selection: $scope) {
                    Text("每次").tag(AnalyticsScope.session)
                    Text("日").tag(AnalyticsScope.day)
                    Text("周").tag(AnalyticsScope.week)
                    Text("年").tag(AnalyticsScope.year)
                }
                .pickerStyle(.segmented)

                LazyVGrid(columns: summaryColumns, spacing: 10) {
                    SummaryMetric(title: "会话数", value: "\(report.summary.sessionCount)")
                    SummaryMetric(title: "完成率", value: percent(report.summary.completionRate))
                    SummaryMetric(title: "总专注", value: duration(report.summary.focusedSeconds))
                    SummaryMetric(title: "平均覆盖率", value: percent(report.summary.averageCoverage))
                }

                if report.rows.isEmpty {
                    ContentUnavailableView("暂无统计", systemImage: "chart.bar.xaxis")
                        .padding(.top, 30)
                } else {
                    AnalyticsChart(scope: scope, report: report)
                    AnalyticsTable(scope: scope, rows: report.rows)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    private var summaryColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 10),
            count: horizontalSizeClass == .regular ? 4 : 2
        )
    }
}

private struct SummaryMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold()).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background, in: .rect(cornerRadius: 14))
    }
}

private struct AnalyticsChart: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let scope: AnalyticsScope
    let report: AnalyticsReport

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(scope == .session ? "状态分布" : "状态趋势")
                .font(.headline)

            if scope == .session {
                statusRing
            } else {
                stackedTrend
            }
        }
        .padding()
        .background(.background, in: .rect(cornerRadius: 14))
    }

    private var visibleSegments: [AnalyticsStatusSegment] {
        report.statusSegments.filter { $0.seconds > 0 }
    }

    private var statusRing: some View {
        Chart(visibleSegments) { segment in
            SectorMark(
                angle: .value("时长", segment.seconds),
                innerRadius: .ratio(0.62),
                angularInset: 2
            )
            .cornerRadius(4)
            .foregroundStyle(by: .value("状态", segment.level.displayName))
            .accessibilityLabel(segment.level.displayName)
            .accessibilityValue(duration(segment.seconds))
        }
        .chartForegroundStyleScale(domain: statusDomain, range: statusColors)
        .chartLegend(position: .bottom, alignment: .center, spacing: 12)
        .chartBackground { proxy in
            GeometryReader { geometry in
                if let frame = proxy.plotFrame {
                    let plotFrame = geometry[frame]
                    VStack(spacing: 3) {
                        Text("统计时长")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(duration(report.breakdown.totalSeconds))
                            .font(.headline)
                            .monospacedDigit()
                    }
                    .position(x: plotFrame.midX, y: plotFrame.midY)
                }
            }
        }
        .frame(height: horizontalSizeClass == .regular ? 320 : 270)
        .accessibilityLabel("专注状态环形图")
    }

    private var stackedTrend: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                trendChart
                    .frame(
                        width: max(
                            geometry.size.width,
                            CGFloat(report.rows.count) * periodWidth
                        ),
                        height: 270
                    )
            }
            .scrollIndicators(.visible)
        }
        .frame(height: 270)
        .accessibilityLabel("专注状态堆叠柱状趋势图")
    }

    private var trendChart: some View {
        Chart {
            ForEach(Array(report.rows.reversed())) { row in
                ForEach(row.statusSegments.filter { $0.seconds > 0 }) { segment in
                    BarMark(
                        x: .value("周期", row.title),
                        y: .value("分钟", segment.seconds / 60)
                    )
                    .foregroundStyle(by: .value("状态", segment.level.displayName))
                    .accessibilityLabel("\(row.title) · \(segment.level.displayName)")
                    .accessibilityValue(duration(segment.seconds))
                }
            }
        }
        .chartForegroundStyleScale(domain: statusDomain, range: statusColors)
        .chartLegend(position: .bottom, alignment: .center, spacing: 12)
        .chartXAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(.clear)
                AxisTick()
                AxisValueLabel().font(.caption2)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let minutes = value.as(Double.self) {
                        Text(duration(minutes * 60))
                    }
                }
            }
        }
    }

    private var periodWidth: CGFloat {
        horizontalSizeClass == .regular ? 64 : 78
    }

    private var statusDomain: [String] {
        FocusLevel.allCases.map(\.displayName)
    }

    private var statusColors: [Color] {
        [.green, .orange, .red, .gray.opacity(0.55)]
    }
}

private struct AnalyticsTable: View {
    let scope: AnalyticsScope
    let rows: [AnalyticsRow]

    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 0) {
                GridRow { headers }
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Divider().gridCellColumns(scope == .session ? 9 : 10)
                ForEach(rows) { row in
                    GridRow { cells(row) }
                        .font(.caption)
                        .padding(.vertical, 10)
                    Divider().gridCellColumns(scope == .session ? 9 : 10)
                }
            }
            .padding()
            .background(.background, in: .rect(cornerRadius: 14))
        }
    }

    @ViewBuilder private var headers: some View {
        if scope == .session {
            tableText("日期", 115); tableText("任务", 180); tableText("状态", 52)
            tableText("实际时长", 75); tableText("专注", 62); tableText("走神", 62)
            tableText("分心", 62); tableText("未观测", 62); tableText("覆盖率", 58)
        } else {
            tableText("周期", 110); tableText("会话数", 52); tableText("完成率", 58)
            tableText("总时长", 70); tableText("专注", 62); tableText("走神", 62)
            tableText("分心", 62); tableText("未观测", 62); tableText("覆盖率", 58)
        }
    }

    @ViewBuilder private func cells(_ row: AnalyticsRow) -> some View {
        if scope == .session {
            tableText(row.periodStart.formatted(date: .numeric, time: .shortened), 115)
            tableText(row.title, 180, lineLimit: 2)
            tableText(row.status == .completed ? "完成" : "提前结束", 52)
        } else {
            tableText(row.title, 110)
            tableText("\(row.sessionCount)", 52)
            tableText(percent(row.completionRate), 58)
        }
        tableText(duration(row.totalSeconds), 75)
        tableText(duration(row.breakdown.focusedSeconds), 62)
        tableText(duration(row.breakdown.wanderingSeconds), 62)
        tableText(duration(row.breakdown.distractedSeconds), 62)
        tableText(duration(row.breakdown.unknownSeconds), 62)
        tableText(percent(row.coverage), 58)
    }

    private func tableText(_ value: String, _ width: CGFloat, lineLimit: Int = 1) -> some View {
        Text(value).lineLimit(lineLimit).frame(width: width, alignment: .leading)
    }
}

private struct SessionRow: View {
    let session: FocusSession

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(session.goal).font(.headline).lineLimit(2)
            HStack(spacing: 12) {
                Label(duration(session.duration), systemImage: "timer")
                Label(session.plannedStart.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            MetricBar(breakdown: session.breakdown).frame(height: 7)
        }
        .padding(.vertical, 5)
    }
}

private func duration(_ seconds: TimeInterval) -> String {
    let totalMinutes = max(0, Int(seconds / 60))
    if totalMinutes >= 60 { return "\(totalMinutes / 60)时\(totalMinutes % 60)分" }
    return "\(totalMinutes)分"
}

private func percent(_ value: Double) -> String {
    "\(Int((min(max(value, 0), 1) * 100).rounded()))%"
}
