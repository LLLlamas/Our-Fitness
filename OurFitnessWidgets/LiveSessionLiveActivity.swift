// Live Activity UI for an in-progress Live Session.
//
// Renders the Lock Screen banner + Dynamic Island (compact / minimal / expanded)
// for a running Live Session. The timer counts on the SYSTEM side via
// `Text(timerInterval:)` — the app does not have to be running for the seconds to
// advance, which is the whole point of the Live Activity.
//
// Source of truth is `attributes.startDate` (the same anchor the app persists in
// LiveSessionStore). `state.expectedMinutes` gives the planned end; once the
// timer passes it, `Text(timerInterval:)` keeps counting (it counts up from start
// with no cap), and we tint toward the "over time" accent.
//
// Styling note: a widget extension cannot read the app's Theme environment, so we
// use a small static palette here (warm accents that read on both Lock Screen
// backgrounds). Keep it legible and self-contained.

#if canImport(ActivityKit)
import ActivityKit
import SwiftUI
import WidgetKit

@available(iOS 16.2, *)
private enum LSPalette {
    static let accent = Color(red: 0.96, green: 0.58, blue: 0.20)   // warm amber, on-brand
    static let text = Color.primary
    static let dim = Color.secondary
}

@available(iOS 16.2, *)
struct LiveSessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveSessionAttributes.self) { context in
            // Lock Screen / banner presentation.
            LockScreenLiveSessionView(context: context)
                .padding(16)
                .activityBackgroundTint(Color.black.opacity(0.35))
                .activitySystemActionForegroundColor(LSPalette.accent)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(context.attributes.activityName)
                            .font(.headline)
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: context.attributes.symbol)
                            .foregroundStyle(LSPalette.accent)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.expectedMinutes) min plan")
                        .font(.caption)
                        .foregroundStyle(LSPalette.dim)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(timerInterval: timerRange(context), countsDown: false)
                        .font(.system(size: 34, weight: .semibold, design: .monospaced))
                        .foregroundStyle(LSPalette.accent)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            } compactLeading: {
                Image(systemName: context.attributes.symbol)
                    .foregroundStyle(LSPalette.accent)
            } compactTrailing: {
                Text(timerInterval: timerRange(context), countsDown: false)
                    .monospacedDigit()
                    .foregroundStyle(LSPalette.accent)
                    .frame(maxWidth: 54)
            } minimal: {
                Image(systemName: context.attributes.symbol)
                    .foregroundStyle(LSPalette.accent)
            }
            .keylineTint(LSPalette.accent)
        }
    }

    /// Range fed to `Text(timerInterval:)`. We start at the session's start anchor
    /// and end at a far-future bound so the timer keeps counting up past the
    /// planned time (the activity is ended explicitly by the app, not by the
    /// timer hitting an end). The lower bound is the real start, so the displayed
    /// elapsed time matches the app exactly.
    private func timerRange(_ context: ActivityViewContext<LiveSessionAttributes>) -> ClosedRange<Date> {
        let start = context.attributes.startDate
        // 24h ceiling — generous upper bound; sessions are minutes, not days.
        return start...start.addingTimeInterval(60 * 60 * 24)
    }
}

@available(iOS 16.2, *)
private struct LockScreenLiveSessionView: View {
    let context: ActivityViewContext<LiveSessionAttributes>

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: context.attributes.symbol)
                .font(.system(size: 30))
                .foregroundStyle(LSPalette.accent)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(context.attributes.activityName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(LSPalette.text)
                    .lineLimit(1)
                Text("Live session · \(context.state.expectedMinutes) min planned")
                    .font(.caption)
                    .foregroundStyle(LSPalette.dim)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(timerInterval: range, countsDown: false)
                .font(.system(size: 30, weight: .semibold, design: .monospaced))
                .foregroundStyle(LSPalette.accent)
                .frame(minWidth: 90, alignment: .trailing)
        }
    }

    private var range: ClosedRange<Date> {
        let start = context.attributes.startDate
        return start...start.addingTimeInterval(60 * 60 * 24)
    }
}
#endif
