// Live session surface for the watch's Train tab — the wrist mirror of the
// phone's Features/Workouts/LiveSessionCard.swift.
//
// Two states, exactly like the phone's card:
//   • no session  -> a pushed activity picker (activity tap -> duration sheet -> start)
//   • one running -> the runner: elapsed, planned length, live calorie readout, End
//
// TIMESTAMP-ANCHORED, NOT A TICKING COUNTER. `LiveSessionSnapshot.startDate` is
// the only truth; elapsed is ALWAYS recomputed as now − startDate. TimelineView
// drives the DISPLAY once a second, so the readout stays correct across wrist-
// down, app suspension and relaunch — a Timer incrementing a stored counter
// would drift to zero the moment watchOS suspends us. Same reasoning as
// Domain/LiveSessionState.swift's header; do not "optimise" it into a counter.
//
// The phone owns the session: we never write an ActivitySession here, we only
// send .startLiveSession / .endLiveSession and render what comes back.

import SwiftUI
import WatchKit

struct WatchLiveSessionView: View {
    @EnvironmentObject private var store: WatchSyncStore

    var body: some View {
        if let session = store.liveSession {
            runnerSection(session)
        } else {
            idleSection
        }
    }

    // MARK: Idle

    private var idleSection: some View {
        Section("Live session") {
            NavigationLink {
                ActivityPickerView()
            } label: {
                Label("Start a session", systemImage: "play.circle.fill")
                    .font(.headline)
            }
        }
    }

    // MARK: Runner

    @ViewBuilder
    private func runnerSection(_ session: LiveSessionSnapshot) -> some View {
        Section("Live session") {
            // Ticks the display only — see the file header. context.date is the
            // real clock, so a suspended-then-resumed watch simply catches up.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let elapsed = elapsedSeconds(session, now: context.date)
                let expectedSeconds = max(1, session.expectedMinutes * 60)
                let overtime = elapsed > expectedSeconds
                let liveCal = Int(CalorieEstimator.caloriesForActivity(
                    met: session.met,
                    minutes: Double(elapsed) / 60.0,
                    bodyWeightLb: store.bodyWeightLb
                ).rounded())

                VStack(alignment: .leading, spacing: 6) {
                    Label(session.activityName, systemImage: symbol(for: session))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(timeString(elapsed))
                        .font(.system(.title, design: .monospaced).weight(.semibold))
                        .foregroundStyle(overtime ? .orange : .primary)

                    ProgressView(
                        value: Double(min(elapsed, expectedSeconds)),
                        total: Double(expectedSeconds)
                    )
                    .tint(overtime ? .orange : .green)

                    Text(overtime
                         ? "past \(session.expectedMinutes) min planned"
                         : "of \(session.expectedMinutes) min")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    // "cal" not "kcal" — house rule.
                    Text("≈ \(liveCal) cal")
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }

            EndSessionButton(session: session)
        }
    }

    /// Same derivation as `LiveSessionState.elapsedSeconds(now:)`. The wire
    /// snapshot carries the anchor without the phone-side `profileId` that
    /// `LiveSessionState` requires, so we apply the formula to it directly
    /// rather than fabricating a state value.
    private func elapsedSeconds(_ session: LiveSessionSnapshot, now: Date) -> Int {
        max(0, Int(now.timeIntervalSince(session.startDate)))
    }

    private func symbol(for session: LiveSessionSnapshot) -> String {
        ActivityCatalog.activity(id: session.activityId)?.symbol ?? "figure.mixed.cardio"
    }

    private func timeString(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - End button

/// Split out so the one-shot `ended` guard isn't reset by TimelineView's
/// per-second re-render, and so a double tap can't queue two end actions.
private struct EndSessionButton: View {
    @EnvironmentObject private var store: WatchSyncStore
    let session: LiveSessionSnapshot

    @State private var ended = false

    var body: some View {
        Button(role: .destructive) {
            guard !ended else { return }
            ended = true
            WKInterfaceDevice.current().play(.success)
            // startDate rides along so the phone can reject a stale queued end
            // (e.g. sent offline, delivered after a different session started).
            store.send(.endLiveSession(
                startDate: session.startDate,
                elapsedSeconds: max(0, Int(Date().timeIntervalSince(session.startDate)))
            ))
        } label: {
            Label("End session", systemImage: "stop.circle.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .disabled(ended)
    }
}

// MARK: - Activity picker

/// One pushed screen listing the whole catalog. Picking an activity raises the
/// duration sheet, and a preset tap there both confirms and starts — two taps
/// plus a confirm, which is the whole budget a wrist deserves.
///
/// The catalog is a compile-time constant in the watch target, so this screen
/// works with no sync at all.
private struct ActivityPickerView: View {
    @EnvironmentObject private var store: WatchSyncStore
    @Environment(\.dismiss) private var dismiss

    @State private var pending: Activity?

    var body: some View {
        List {
            ForEach(ActivityCatalog.all) { activity in
                Button {
                    WKInterfaceDevice.current().play(.click)
                    pending = activity
                } label: {
                    Label(activity.name, systemImage: activity.symbol)
                        .font(.headline)
                        .lineLimit(1)
                }
            }
        }
        .navigationTitle("Activity")
        .sheet(item: $pending) { activity in
            DurationSheet(activity: activity) { minutes in
                start(activity, minutes: minutes)
            }
        }
    }

    private func start(_ activity: Activity, minutes: Int) {
        WKInterfaceDevice.current().play(.success)
        // "Other" already carries ActivityCatalog.otherDefaultMET as its MET, so
        // there's no custom-intensity slider to mirror from the phone here.
        store.send(.startLiveSession(
            activityId: activity.id,
            activityName: activity.name,
            met: activity.met,
            expectedMinutes: minutes,
            startDate: Date()
        ))
        pending = nil
        dismiss()   // back to Train, where the runner takes over
    }
}

private struct DurationSheet: View {
    let activity: Activity
    let onPick: (Int) -> Void

    var body: some View {
        List {
            Section {
                ForEach(ActivityCatalog.durationPresets, id: \.self) { minutes in
                    Button {
                        onPick(minutes)
                    } label: {
                        Text("\(minutes) min")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            } header: {
                Label(activity.name, systemImage: activity.symbol)
                    .lineLimit(1)
            } footer: {
                Text("You can run past it — this just sets the target.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
