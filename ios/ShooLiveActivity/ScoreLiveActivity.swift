import ActivityKit
import SwiftUI
import WidgetKit

/// EX-03: running score only. Placeholder UI — final design from the designer.
struct ScoreLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ScoreActivityAttributes.self) { context in
            HStack {
                Text("Shoo")
                    .font(.headline)
                Spacer()
                Text("\(context.state.score)%")
                    .font(.title2.monospacedDigit().bold())
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.domain)
                        .font(.caption)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.score)%")
                        .font(.title3.monospacedDigit().bold())
                }
            } compactLeading: {
                Image(systemName: "shield.lefthalf.filled")
            } compactTrailing: {
                Text("\(context.state.score)%")
                    .monospacedDigit()
            } minimal: {
                Text("\(context.state.score)")
                    .monospacedDigit()
            }
        }
    }
}
