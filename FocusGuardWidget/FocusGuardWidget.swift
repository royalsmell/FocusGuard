import ActivityKit
import SwiftUI
import WidgetKit

@main
struct FocusGuardWidgetBundle: WidgetBundle {
    var body: some Widget {
        FocusGuardLiveActivity()
    }
}

struct FocusGuardLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            HStack(spacing: 14) {
                Image(systemName: "scope")
                    .font(.title2)
                    .foregroundStyle(.indigo)
                VStack(alignment: .leading, spacing: 3) {
                    Text(context.attributes.goal)
                        .font(.headline)
                        .lineLimit(1)
                    Text(timerInterval: Date.now...max(Date.now, context.attributes.endsAt), countsDown: true)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .activityBackgroundTint(Color.indigo.opacity(0.12))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "scope")
                        .foregroundStyle(.indigo)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.goal)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: Date.now...max(Date.now, context.attributes.endsAt), countsDown: true)
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "scope")
                    .foregroundStyle(.indigo)
            } compactTrailing: {
                Text(timerInterval: Date.now...max(Date.now, context.attributes.endsAt), countsDown: true)
                    .monospacedDigit()
                    .frame(width: 42)
            } minimal: {
                Image(systemName: "scope")
                    .foregroundStyle(.indigo)
            }
        }
    }
}
