import XCTest

// Pure Domain. `now` is pinned (the project's standard fixed clock — never a
// bare Date(), see CLAUDE.md CI rules) and a fixed non-UTC calendar is threaded
// into every call, so day grouping never depends on the host machine's zone.
//
// Date(timeIntervalSince1970: 1_780_488_000) is 2026-06-03 12:00:00 UTC, which
// is Wednesday 2026-06-03 08:00 local in America/New_York.
//
// WHY THIS FILE EXISTS: this is the medication RECORD. Its failure modes are
// losing a dose, attributing one to the wrong day, or showing a day's doses out
// of order — all three would be invisible on screen and all three would make
// the record wrong in the one conversation it exists for.
final class MedicationHistoryTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_780_488_000)

    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        return cal
    }()

    private var today: Date { calendar.startOfDay(for: now) }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: today)!
    }

    private func instant(_ offset: Int, hour: Int, minute: Int = 0) -> Date {
        var comps = calendar.dateComponents([.year, .month, .day], from: day(offset))
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        return calendar.date(from: comps)!
    }

    // MARK: - Fixtures

    private let userId = UUID()
    private let groupId = UUID()

    private func medication(_ name: String, dosage: String? = nil,
                            scheduledMinutesOfDay: [Int] = []) -> ReminderDTO {
        ReminderDTO(
            userId: userId, groupId: groupId, name: name, intervalDays: 1,
            dosage: dosage, scheduledMinutesOfDay: scheduledMinutesOfDay
        )
    }

    private func event(_ reminder: ReminderDTO, at when: Date, dosageTaken: String? = nil) -> ReminderEventDTO {
        ReminderEventDTO(
            userId: userId, reminderId: reminder.id,
            date: "ignored-by-this-file", timestamp: when, dosageTaken: dosageTaken
        )
    }

    // MARK: - Joining

    func test_entries_carry_the_medication_name_dosage_and_set_time() throws {
        let med = medication("Vitamin D", dosage: "1 tablet", scheduledMinutesOfDay: [8 * 60])
        let entries = MedicationHistory.entries(
            events: [event(med, at: instant(0, hour: 8, minute: 4), dosageTaken: "2 tablets")],
            medications: [med]
        )
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.medicationName, "Vitamin D")
        XCTAssertEqual(entry.recommendedDosage, "1 tablet")
        XCTAssertEqual(entry.dosageTaken, "2 tablets", "what was taken, not what was recommended")
        XCTAssertEqual(entry.scheduledMinutesOfDay, [8 * 60])
    }

    /// The join is also the filter: a plant watering shares the event table with
    /// medication doses and must never reach the medication record.
    func test_entries_drop_events_that_belong_to_no_known_medication() {
        let med = medication("Vitamin D")
        let watering = ReminderEventDTO(
            userId: userId, reminderId: UUID(), date: "x", timestamp: instant(0, hour: 9)
        )
        let entries = MedicationHistory.entries(
            events: [event(med, at: instant(0, hour: 8)), watering],
            medications: [med]
        )
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.reminderId, med.id)
    }

    // MARK: - Grouping

    func test_byDay_puts_newest_days_first_and_doses_within_a_day_in_order() throws {
        let med = medication("Metformin")
        // Handed over deliberately scrambled: the caller's order must not matter.
        let entries = MedicationHistory.entries(
            events: [
                event(med, at: instant(-1, hour: 21)),
                event(med, at: instant(0, hour: 20)),
                event(med, at: instant(0, hour: 8)),
                event(med, at: instant(-1, hour: 8, minute: 30)),
                event(med, at: instant(0, hour: 13)),
            ],
            medications: [med]
        )
        let days = MedicationHistory.byDay(entries, calendar: calendar)

        XCTAssertEqual(days.map(\.id), [day(0), day(-1)], "newest day first")
        XCTAssertEqual(days[0].entries.map { calendar.component(.hour, from: $0.timestamp) },
                       [8, 13, 20], "earliest dose first inside a day")
        XCTAssertEqual(days[1].entries.map { calendar.component(.hour, from: $0.timestamp) },
                       [8, 21])
    }

    /// Midnight is the boundary, and it belongs to the new day — the single
    /// most likely place for a dose to be filed against the wrong date.
    func test_byDay_files_a_dose_just_after_midnight_on_the_new_day() {
        let med = medication("Bedtime pill")
        let entries = MedicationHistory.entries(
            events: [
                event(med, at: instant(-1, hour: 23, minute: 58)),
                event(med, at: instant(0, hour: 0, minute: 2)),
            ],
            medications: [med]
        )
        let days = MedicationHistory.byDay(entries, calendar: calendar)
        XCTAssertEqual(days.count, 2)
        XCTAssertEqual(days[0].id, day(0))
        XCTAssertEqual(days[0].doseCount, 1)
        XCTAssertEqual(days[1].id, day(-1))
        XCTAssertEqual(days[1].doseCount, 1)
    }

    func test_day_counts_distinguish_doses_from_medications() {
        let a = medication("Vitamin D")
        let b = medication("Metformin")
        let entries = MedicationHistory.entries(
            events: [
                event(a, at: instant(0, hour: 8)),
                event(b, at: instant(0, hour: 8, minute: 5)),
                event(b, at: instant(0, hour: 20)),
            ],
            medications: [a, b]
        )
        let days = MedicationHistory.byDay(entries, calendar: calendar)
        XCTAssertEqual(days.first?.doseCount, 3)
        XCTAssertEqual(days.first?.medicationCount, 2, "two medications, three doses")
    }

    func test_byDay_for_one_medication_narrows_to_that_medication() {
        let a = medication("Vitamin D")
        let b = medication("Metformin")
        let entries = MedicationHistory.entries(
            events: [event(a, at: instant(0, hour: 8)), event(b, at: instant(0, hour: 9))],
            medications: [a, b]
        )
        let days = MedicationHistory.byDay(entries, reminderId: b.id, calendar: calendar)
        XCTAssertEqual(days.flatMap(\.entries).map(\.medicationName), ["Metformin"])
    }

    func test_totals_are_counted_off_the_rendered_days() {
        let med = medication("Vitamin D")
        let entries = MedicationHistory.entries(
            events: [
                event(med, at: instant(0, hour: 8)),
                event(med, at: instant(0, hour: 20)),
                event(med, at: instant(-2, hour: 8)),
            ],
            medications: [med]
        )
        let totals = MedicationHistory.totals(MedicationHistory.byDay(entries, calendar: calendar))
        XCTAssertEqual(totals.doses, 3)
        XCTAssertEqual(totals.days, 2, "a skipped day is absent, not an empty row")
    }

    func test_empty_input_produces_no_days() {
        XCTAssertTrue(MedicationHistory.byDay([], calendar: calendar).isEmpty)
        let totals = MedicationHistory.totals([])
        XCTAssertEqual(totals.doses, 0)
        XCTAssertEqual(totals.days, 0)
    }

    // MARK: - Day headings

    func test_dayTitle_names_the_recent_past_by_weekday() {
        XCTAssertEqual(MedicationHistory.dayTitle(day(0), now: now, calendar: calendar), "Today")
        XCTAssertEqual(MedicationHistory.dayTitle(day(-1), now: now, calendar: calendar), "Yesterday")
        // `now` is a Wednesday, so three days back is the Sunday.
        XCTAssertEqual(MedicationHistory.dayTitle(day(-3), now: now, calendar: calendar), "Sunday")
        // Beyond a week a weekday name stops identifying a day uniquely, so it
        // becomes a date.
        let old = MedicationHistory.dayTitle(day(-30), now: now, calendar: calendar)
        XCTAssertFalse(["Today", "Yesterday"].contains(old))
        XCTAssertTrue(old.contains("2026"), old)
    }

    // MARK: - Reading a dose against its set time

    func test_timingLabel_is_nil_without_a_set_time_and_states_the_gap_with_one() throws {
        let untimed = medication("Vitamin D")
        let timed = medication("Metformin", scheduledMinutesOfDay: [8 * 60, 20 * 60])

        let entries = MedicationHistory.entries(
            events: [
                event(untimed, at: instant(0, hour: 9, minute: 30)),
                event(timed, at: instant(0, hour: 9, minute: 30)),
            ],
            medications: [untimed, timed]
        )
        XCTAssertNil(MedicationHistory.timingLabel(entries[0], calendar: calendar))

        let label = try XCTUnwrap(MedicationHistory.timingLabel(entries[1], calendar: calendar))
        XCTAssertTrue(label.hasPrefix("1 hr 30 min after "), label)
    }

    func test_minutesFromScheduled_matches_the_pattern_math() {
        let med = medication("Metformin", scheduledMinutesOfDay: [8 * 60, 20 * 60])
        let entries = MedicationHistory.entries(
            events: [event(med, at: instant(0, hour: 7, minute: 45))], medications: [med]
        )
        XCTAssertEqual(MedicationHistory.minutesFromScheduled(entries[0], calendar: calendar), -15)
    }
}
