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
// use a small static palette here. Both accents are mid-luminance and are used
// only as foreground/tint colours over the dark activity background — never as a
// fill behind text — so they stay legible on the Lock Screen and Dynamic Island.
// Keep it legible and self-contained.

#if canImport(ActivityKit)
import ActivityKit
import SwiftUI
import WidgetKit

@available(iOS 16.2, *)
private enum LSPalette {
    // Mirrors Theme.standard in OurFitness/Services/Theme.swift (accent / accent2).
    // Copied, not imported: the widget target doesn't compile Theme.
    static let accent = Color(red: 0.498, green: 0.631, blue: 0.447)   // sage — icons, keyline
    static let accent2 = Color(red: 0.788, green: 0.482, blue: 0.353)  // terracotta — running timer
    static let text = Color.primary
    static let dim = Color.secondary
    // Lock Screen banner matches the app's light palette (Theme.bg / text / dim).
    // The Dynamic Island is always black, so it keeps the adaptive text colours above.
    static let lockBackground = Color(red: 0.969, green: 0.953, blue: 0.925)
    static let lockText = Color(red: 0.102, green: 0.086, blue: 0.078)
    static let lockDim = Color(red: 0.478, green: 0.451, blue: 0.408)
}

@available(iOS 16.2, *)
struct LiveSessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveSessionAttributes.self) { context in
            // Lock Screen / banner presentation.
            LockScreenLiveSessionView(context: context)
                .padding(16)
                .activityBackgroundTint(LSPalette.lockBackground)
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
                        .foregroundStyle(LSPalette.accent2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            } compactLeading: {
                Image(systemName: context.attributes.symbol)
                    .foregroundStyle(LSPalette.accent)
            } compactTrailing: {
                Text(timerInterval: timerRange(context), countsDown: false)
                    .monospacedDigit()
                    .foregroundStyle(LSPalette.accent2)
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
                    .foregroundStyle(LSPalette.lockText)
                    .lineLimit(1)
                Text("Live session · \(context.state.expectedMinutes) min planned")
                    .font(.caption)
                    .foregroundStyle(LSPalette.lockDim)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(timerInterval: range, countsDown: false)
                .font(.system(size: 30, weight: .semibold, design: .monospaced))
                .foregroundStyle(LSPalette.accent2)
                .frame(minWidth: 90, alignment: .trailing)
        }
    }

    private var range: ClosedRange<Date> {
        let start = context.attributes.startDate
        return start...start.addingTimeInterval(60 * 60 * 24)
    }
}
#endif
