// The in-app half of a medication reminder.
//
// A notification only exists at the instant it fires. If the app is already
// open, or the banner was swiped away, or the phone was face-down in a Focus
// mode, nothing afterwards says a dose is still unlogged. This is that
// something: it sits under the header on every tab, for as long as the day has
// called for more doses than have been logged.
//
// It reads state rather than listening for a notification, so it is right
// whether or not one ever fired — including when notification permission was
// refused outright.
//
// Only medications with SET TIMES appear. An inferred pattern is a guess about
// a habit; putting a persistent "you haven't logged this" banner behind a guess
// would be the app asserting something about a dose it cannot know.

import SwiftUI
import SwiftData

struct MedicationDueBanner: View {
    let profile: ProfileDTO

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @EnvironmentObject private var toasts: ToastCenter

    @Query private var groupModels: [ReminderGroupModel]
    @Query private var reminderModels: [ReminderModel]
    @Query private var eventModels: [ReminderEventModel]

    /// Re-evaluated on a timer so a dose time that passes while the app is open
    /// brings the banner in on its own. A minute is fine: these are wall-clock
    /// times a person set by hand, not deadlines.
    @State private var now = Date()

    private let tick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    init(profile: ProfileDTO) {
        self.profile = profile
        let uid = profile.id
        let dayStart = Calendar.current.startOfDay(for: Date())
        _groupModels = Query(filter: #Predicate<ReminderGroupModel> { $0.userId == uid })
        _reminderModels = Query(filter: #Predicate<ReminderModel> { $0.userId == uid }, sort: \.name)
        // A lower BOUND, not the day filter. This view is created once and lives
        // in RootView for the whole session, so `dayStart` is frozen at whatever
        // day the app was launched on — which is why the day itself is applied
        // in `logCountByReminder` against the ticking `now` instead. Keeping the
        // bound in the predicate still stops the query dragging in the entire
        // event history.
        _eventModels = Query(
            filter: #Predicate<ReminderEventModel> { $0.userId == uid && $0.timestamp >= dayStart }
        )
    }

    private var medicationGroupId: UUID? {
        groupModels.first { $0.kindRaw == ReminderGroupKind.medication.rawValue }?.id
    }

    /// Medications with at least one set time. Predicate-scoped by profile
    /// above; this narrowing is by group and by whether a time was set, neither
    /// of which is a per-profile axis.
    private var timedMedications: [ReminderDTO] {
        guard let gid = medicationGroupId else { return [] }
        return reminderModels
            .map(\.snapshot)
            .filter { $0.groupId == gid && !$0.scheduledMinutesOfDay.isEmpty }
    }

    /// Today's log count per reminder, where "today" is the day of the ticking
    /// `now` — NOT the day this view was initialised on.
    ///
    /// Left to the query's frozen `dayStart` bound alone, an app that stayed
    /// alive past midnight counted YESTERDAY's doses against today's set times:
    /// three logged yesterday meant three times had to come round again before
    /// the banner could ever reappear, so a medication's in-app alert went
    /// quiet from the second day onwards — silently, and for the one surface
    /// that's meant to be right even when notifications are off.
    private func logCountByReminder(on day: Date, calendar: Calendar) -> [UUID: Int] {
        eventModels.reduce(into: [:]) { counts, e in
            guard calendar.isDate(e.timestamp, inSameDayAs: day) else { return }
            counts[e.reminderId, default: 0] += 1
        }
    }

    /// Medications the day has called for more times than have been logged.
    ///
    /// A COUNT comparison, not a per-dose matching: which physical dose a given
    /// log was meant to be is not something the app can know, and guessing
    /// would produce exactly the false "you missed one" claim the medication
    /// copy rules forbid. Two times reached and two logged reads as settled,
    /// whatever order they happened in.
    private var outstanding: [ReminderDTO] {
        let calendar = Calendar.current
        let logs = logCountByReminder(on: now, calendar: calendar)
        return timedMedications.filter { med in
            let reached = MedicationPattern.timesReached(
                med.scheduledMinutesOfDay, now: now, calendar: calendar
            )
            return reached > (logs[med.id] ?? 0)
        }
    }

    var body: some View {
        let due = outstanding
        if let first = due.first {
            Banner(tone: .warn) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(headline(first, othersCount: due.count - 1))
                        .fontWeight(.semibold)
                    Text(subline(first))
                        .font(.caption2)
                        .foregroundStyle(theme.dim)

                    HStack(spacing: 8) {
                        Button("View") {
                            NotificationCenter.default.post(name: .openRemindersTab, object: nil)
                            Haptics.selection()
                        }
                        .tactile(.secondary)

                        Button("Log \(first.name)") { log(first) }
                            .tactile(.primary)
                            .accessibilityLabel("Log a dose of \(first.name)")
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(theme.bg)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: due.count)
            .onReceive(tick) { now = $0 }
        } else {
            // Still needs to exist in the hierarchy, or the timer stops and the
            // banner never appears when a dose time passes mid-session.
            Color.clear
                .frame(height: 0)
                .onReceive(tick) { now = $0 }
        }
    }

    /// States only what the LOG shows. Never "you missed a dose" and never a
    /// dose amount — see the copy rules on ReminderNotificationService.
    private func headline(_ med: ReminderDTO, othersCount: Int) -> String {
        guard othersCount > 0 else { return "\(med.name) isn't logged yet" }
        // Verb agrees with the subject: "and 1 other ISN'T", "and 2 others
        // AREN'T". The claim itself is unchanged — still only about the log.
        guard othersCount > 1 else { return "\(med.name) and 1 other isn't logged yet" }
        return "\(med.name) and \(othersCount) others aren't logged yet"
    }

    private func subline(_ med: ReminderDTO) -> String {
        "Set for \(MedicationPattern.clockList(med.scheduledMinutesOfDay))"
    }

    /// One tap logs a dose now, at the recommended dosage — `logDone` resolves
    /// the amount, exactly as the lock-screen action does.
    private func log(_ med: ReminderDTO) {
        // One instant for the event, the toast and the re-evaluation, so the
        // "Logged at" time can't disagree with the timestamp that was stored.
        let when = Date()
        guard ReminderNotificationService.logDone(ctx, reminderId: med.id, date: when) != nil else { return }
        // ToastCenter.show fires .win's success haptic itself — no Haptics here.
        toasts.show(Toast(
            title: med.name,
            detail: "Logged at \(when.formatted(date: .omitted, time: .shortened))",
            accent: .win, symbol: "pills.fill"
        ))
        now = when
    }
}
