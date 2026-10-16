import XCTest

final class RepHistoryTests: XCTestCase {

    // Pinned clock: Wednesday 2026-05-27 (ISO week starts Monday 05-25). Never a bare Date().
    private let now = ISO8601DateFormatter().date(from: "2026-05-27T12:00:00Z")!
    private let uid = UUID()
    private let iso = ISO8601DateFormatter()

    private func ts(_ day: String, _ hour: Int = 12) -> Date {
        iso.date(from: "\(day)T\(String(format: "%02d", hour)):00:00Z")!
    }

    private var bench: ExerciseDTO {
        ExerciseDTO(id: "bench", name: "Bench Press", category: .compound,
                    muscleGroups: ["chest"], equipment: [.barbell])
    }
    private var pushups: ExerciseDTO {
        ExerciseDTO(id: "pushups", name: "Push-ups", category: .bodyweight,
                    muscleGroups: ["chest"], equipment: [.bodyweight])
    }
    private var baby: ExerciseDTO {
        ExerciseDTO(id: "baby", name: "Lifted Baby", category: .bodyweight,
                    muscleGroups: [], equipment: [], loadLb: 30)
    }
    private var plank: ExerciseDTO {
        ExerciseDTO(id: "plank", name: "Plank", category: .bodyweight,
                    muscleGroups: [], equipment: [], isIsometric: true)
    }
    private var carry: ExerciseDTO {
        ExerciseDTO(id: "carry", name: "Carried Baby", category: .bodyweight,
                    muscleGroups: [], equipment: [], loadLb: 30, kind: .duration)
    }

    private func row(_ ex: ExerciseDTO, _ weight: Double?, _ reps: Int, _ day: String,
                     hour: Int = 12, hold: Int? = nil) -> WorkoutSetDTO {
        WorkoutSetDTO(userId: uid, exerciseId: ex.id, weightLb: weight, reps: reps,
                      timestamp: ts(day, hour), holdSeconds: hold)
    }

    private func lb(_ w: Double) -> String { w.rounded() == w ? "\(Int(w)) lb" : "\(w) lb" }

    // MARK: - Folding

    func test_days_fold_reps_per_exact_weight_newest_first() {
        let rows = [
            row(bench, 50, 10, "2026-05-20"), row(bench, 50, 20, "2026-05-20", hour: 14),
            row(bench, 52.5, 8, "2026-05-20", hour: 15), row(bench, nil, 5, "2026-05-20", hour: 16),
            row(bench, 50, 12, "2026-05-18"),
        ]
        let days = RepHistory.days(for: bench, rows: rows)
        XCTAssertEqual(days.map(\.key), ["2026-05-20", "2026-05-18"])
        let d = days[0]
        XCTAssertEqual(d.lines.map(\.weight.lb), [nil, 50, 52.5], "bodyweight first, then ascending, no rounding buckets")
        XCTAssertEqual(d.lines.map(\.amount), [5, 30, 8])
        XCTAssertEqual(d.totalAmount, 43)
        XCTAssertEqual(d.amount(at: .init(50)), 30)
        XCTAssertNil(d.amount(at: .init(52)))
        XCTAssertEqual(d.heaviestWeightLb, 52.5)
        XCTAssertEqual(d.rowCount, 4)
    }

    func test_one_tap_rows_and_rep_counter_rows_sum_the_same() {
        let taps = (0..<10).map { row(pushups, nil, 1, "2026-05-20", hour: 8 + $0 % 5) }
        let one = [row(pushups, nil, 10, "2026-05-20")]
        let a = RepHistory.days(for: pushups, rows: taps)[0]
        let b = RepHistory.days(for: pushups, rows: one)[0]
        XCTAssertEqual(a.lines, b.lines)
        XCTAssertEqual(a.totalAmount, 10)
        XCTAssertNotEqual(a.rowCount, b.rowCount, "rows differ; progress doesn't care")
    }

    func test_other_exercises_rows_are_ignored() {
        let rows = [row(bench, 50, 10, "2026-05-20"), row(pushups, nil, 99, "2026-05-20")]
        XCTAssertEqual(RepHistory.days(for: bench, rows: rows)[0].totalAmount, 10)
    }

    func test_fixed_load_nil_weight_reads_as_exercise_load_and_stamped_wins() {
        let rows = [
            row(baby, nil, 10, "2026-05-20"),          // legacy row, before stamping
            row(baby, 30, 14, "2026-05-20", hour: 13), // stamped
            row(baby, 32, 6, "2026-05-22"),            // load edited later
        ]
        let days = RepHistory.days(for: baby, rows: rows)
        XCTAssertEqual(days[1].lines.map(\.weight.lb), [30])
        XCTAssertEqual(days[1].lines.map(\.amount), [24])
        XCTAssertEqual(days[0].lines.map(\.weight.lb), [32])
    }

    func test_non_positive_weight_is_no_weight() {
        let d = RepHistory.days(for: bench, rows: [row(bench, 0, 5, "2026-05-20")])[0]
        XCTAssertEqual(d.lines.map(\.weight), [.bodyweight])
    }

    func test_weeks_fold_by_monday_with_iso_edges() {
        let rows = [
            row(bench, 50, 10, "2026-05-24"),  // Sunday: ends the week of Mon 05-18
            row(bench, 50, 7, "2026-05-25"),   // Monday: starts the next
            row(bench, 50, 3, "2026-05-27"),
        ]
        let weeks = RepHistory.weeks(for: bench, rows: rows)
        XCTAssertEqual(weeks.map(\.key), ["2026-05-25", "2026-05-18"])
        XCTAssertEqual(weeks[0].totalAmount, 10)
        XCTAssertEqual(weeks[0].daysTrained, 2)
        XCTAssertEqual(weeks[1].totalAmount, 10)
    }

    func test_holds_track_longest_and_total_seconds() {
        let rows = [
            row(plank, nil, 1, "2026-05-20", hold: 50), row(plank, nil, 1, "2026-05-20", hour: 13, hold: 40),
            row(plank, nil, 1, "2026-05-20", hour: 14, hold: 40),
        ]
        let d = RepHistory.days(for: plank, rows: rows)[0]
        XCTAssertEqual(d.measure, .holdSeconds)
        XCTAssertEqual(d.totalAmount, 130)
        XCTAssertEqual(d.longestHoldSeconds, 50)
        XCTAssertEqual(RepHistory.summary(d, formatWeight: lb), "longest 50 s · total 2 min 10 s")
    }

    func test_duration_exercise_reads_reps_as_minutes() {
        let d = RepHistory.days(for: carry, rows: [row(carry, nil, 7, "2026-05-20"), row(carry, 30, 5, "2026-05-20", hour: 13)])[0]
        XCTAssertEqual(d.measure, .minutes)
        XCTAssertEqual(d.totalAmount, 12)
        XCTAssertEqual(d.lines.map(\.weight.lb), [30], "nil row is read at the fixed 30 lb load")
        XCTAssertEqual(RepHistory.summary(d, formatWeight: lb), "30 lb × 12 min")
    }

    func test_lastWeightLb_is_the_newest_weighted_row_ever() {
        let rows = [row(bench, 45, 5, "2026-01-05"), row(bench, 55, 5, "2026-03-05"), row(bench, nil, 5, "2026-05-01")]
        XCTAssertEqual(RepHistory.lastWeightLb(for: bench, rows: rows), 55)
        XCTAssertNil(RepHistory.lastWeightLb(for: bench, rows: [row(bench, nil, 5, "2026-05-01")]))
        XCTAssertEqual(RepHistory.lastWeightLb(for: baby, rows: [row(baby, nil, 5, "2026-05-01")]), 30)
    }

    // MARK: - Reference days

    func test_lastTime_is_the_most_recent_earlier_day() {
        let days = RepHistory.days(for: bench, rows: [
            row(bench, 50, 30, "2026-05-14"), row(bench, 50, 20, "2026-05-20"), row(bench, 55, 5, "2026-05-22"),
        ])
        XCTAssertEqual(RepHistory.lastTime(before: "2026-05-27", days: days)?.key, "2026-05-22")
        XCTAssertEqual(RepHistory.lastTime(before: "2026-05-22", days: days)?.key, "2026-05-20")
        XCTAssertNil(RepHistory.lastTime(before: "2026-05-14", days: days))
        XCTAssertEqual(RepHistory.lastTime(at: .init(50), before: "2026-05-27", days: days)?.key, "2026-05-20")
        XCTAssertNil(RepHistory.lastTime(at: .init(60), before: "2026-05-27", days: days))
    }

    func test_sameDayLastWeek_prefers_the_same_weekday() {
        let days = RepHistory.days(for: bench, rows: [row(bench, 50, 20, "2026-05-20"), row(bench, 50, 9, "2026-05-21")])
        let ref = RepHistory.sameDayLastWeek(for: "2026-05-27", days: days)
        XCTAssertEqual(ref?.tally.key, "2026-05-20")
        XCTAssertEqual(ref?.isSameWeekday, true)
    }

    func test_sameDayLastWeek_falls_back_to_the_nearest_day_in_that_iso_week() {
        // Not done last Wednesday; Thursday (1 day off) beats Monday (2 off).
        let days = RepHistory.days(for: bench, rows: [row(bench, 50, 9, "2026-05-18"), row(bench, 50, 7, "2026-05-21")])
        let ref = RepHistory.sameDayLastWeek(for: "2026-05-27", days: days)
        XCTAssertEqual(ref?.tally.key, "2026-05-21")
        XCTAssertEqual(ref?.isSameWeekday, false)
    }

    func test_sameDayLastWeek_tie_goes_to_the_earlier_day() {
        let days = RepHistory.days(for: bench, rows: [row(bench, 50, 9, "2026-05-19"), row(bench, 50, 7, "2026-05-21")])
        XCTAssertEqual(RepHistory.sameDayLastWeek(for: "2026-05-27", days: days)?.tally.key, "2026-05-19")
    }

    func test_sameDayLastWeek_is_nil_when_nothing_was_logged_that_week() {
        // 05-12 is two weeks back; the day itself (05-27) and this week don't count either.
        let days = RepHistory.days(for: bench, rows: [row(bench, 50, 9, "2026-05-12"), row(bench, 50, 5, "2026-05-26")])
        XCTAssertNil(RepHistory.sameDayLastWeek(for: "2026-05-27", days: days))
    }

    // MARK: - Comparison

    func test_compare_gives_deltas_in_both_directions_new_weight_and_not_done() {
        let a = RepHistory.days(for: bench, rows: [
            row(bench, 50, 34, "2026-05-27"), row(bench, 55, 8, "2026-05-27", hour: 13), row(bench, 60, 5, "2026-05-27", hour: 14),
        ])[0]
        let b = RepHistory.days(for: bench, rows: [
            row(bench, 50, 30, "2026-05-20"), row(bench, 55, 10, "2026-05-20", hour: 13), row(bench, 45, 12, "2026-05-20", hour: 14),
            row(bench, 60, 5, "2026-05-20", hour: 15),
        ])[0]
        let c = RepHistory.compare(a, to: b)
        XCTAssertEqual(c.weights.map(\.weight.lb), [45, 50, 55, 60])
        XCTAssertEqual(c.weights.map(\.outcome), [.notDone, .more(4), .fewer(2), .same])
        XCTAssertEqual(c.weights[0].reference, 12)
        XCTAssertNil(c.weights[0].current)
        XCTAssertEqual(c.currentTotal, 47)
        XCTAssertEqual(c.referenceTotal, 57)
        XCTAssertEqual(c.totalDelta, -10)

        let newWeight = RepHistory.compare(a, to: RepHistory.days(for: bench, rows: [row(bench, 50, 30, "2026-05-20")])[0])
        XCTAssertEqual(newWeight.weights.map(\.outcome), [.more(4), .newWeight, .newWeight])
    }

    func test_compare_hold_longest_delta() {
        let a = RepHistory.days(for: plank, rows: [row(plank, nil, 1, "2026-05-27", hold: 55)])[0]
        let b = RepHistory.days(for: plank, rows: [row(plank, nil, 1, "2026-05-20", hold: 60)])[0]
        XCTAssertEqual(RepHistory.compare(a, to: b).longestHoldDelta, -5)
    }

    func test_delta_text_is_plain_in_both_directions() {
        XCTAssertEqual(RepHistory.deltaText(.more(4), reference: "last time"), "+4 vs last time")
        XCTAssertEqual(RepHistory.deltaText(.fewer(4), reference: "Tue"), "4 fewer than Tue")
        XCTAssertEqual(RepHistory.deltaText(.same, reference: "Tue"), "same as Tue")
        XCTAssertEqual(RepHistory.deltaText(.newWeight, reference: "Tue"), "new weight")
        XCTAssertNil(RepHistory.deltaText(.notDone, reference: "Tue"))
        XCTAssertEqual(RepHistory.liveDeltaText(.fewer(12), reference: "last time"), "12 to match last time")
        XCTAssertEqual(RepHistory.liveDeltaText(.more(2), reference: "last week"), "+2 vs last week")
    }

    // MARK: - Bests

    func test_bests_per_weight_heaviest_and_ties_keep_the_earliest_day() {
        let days = RepHistory.days(for: bench, rows: [
            row(bench, 50, 30, "2026-05-10"), row(bench, 50, 30, "2026-05-12"),
            row(bench, 50, 25, "2026-05-14"), row(bench, 60, 5, "2026-05-14", hour: 13),
        ])
        let b = RepHistory.bests(from: days)
        XCTAssertEqual(b.best(at: .init(50))?.amount, 30)
        XCTAssertEqual(b.best(at: .init(50))?.dayKey, "2026-05-10")
        XCTAssertEqual(b.best(at: .init(60))?.amount, 5)
        XCTAssertEqual(b.heaviest, RepHistory.WeightMark(lb: 60, dayKey: "2026-05-14"))
        XCTAssertEqual(b.bestDay, RepHistory.DayBest(amount: 30, dayKey: "2026-05-10"))
        XCTAssertEqual(b.dayCount, 3)
    }

    private func history() -> [WorkoutSetDTO] {
        [row(bench, 50, 30, "2026-05-18"), row(bench, 50, 28, "2026-05-20")]
    }

    func test_newBest_fires_once_on_the_row_that_crosses_the_best_day() {
        var rows = history()
        func log(_ reps: Int, hour: Int) -> RepHistory.NewBest? {
            let r = row(bench, 50, reps, "2026-05-27", hour: hour)
            let result = RepHistory.newBest(after: r, exercise: bench, rows: rows + [r])
            rows.append(r)
            return result
        }
        XCTAssertNil(log(20, hour: 8))
        XCTAssertNil(log(10, hour: 9), "30 ties the best, doesn't beat it")
        XCTAssertEqual(
            log(5, hour: 10),
            .atWeight(measure: .reps, weight: .init(50), amount: 35, previousBest: 30, previousDayKey: "2026-05-18"))
        XCTAssertNil(log(3, hour: 11), "already announced today")
    }

    func test_newBest_works_with_one_tap_rows_and_excludes_the_new_row_from_history() {
        var rows = history()
        var fired = 0
        for i in 0..<35 {
            let tap = row(bench, 50, 1, "2026-05-27", hour: 6 + i % 10)
            rows.append(tap)
            // `rows` already contains the new row here: it must not count as history.
            if RepHistory.newBest(after: tap, exercise: bench, rows: rows) != nil { fired += 1 }
        }
        XCTAssertEqual(fired, 1)
    }

    func test_newBest_needs_two_earlier_days() {
        let one = [row(bench, 50, 10, "2026-05-18")]
        let r = row(bench, 50, 40, "2026-05-27")
        XCTAssertNil(RepHistory.newBest(after: r, exercise: bench, rows: one))
        XCTAssertNotNil(RepHistory.newBest(after: r, exercise: bench, rows: one + [row(bench, 50, 12, "2026-05-20")]))
    }

    func test_newBest_is_per_weight_so_heavier_for_fewer_is_never_a_best_at_the_lighter_weight() {
        let r = row(bench, 50, 5, "2026-05-27")   // far below the 50 lb best of 30
        XCTAssertNil(RepHistory.newBest(after: r, exercise: bench, rows: history() + [r]))
        // A weight never done earlier has no best to beat, so reps alone don't announce.
        let other = row(bench, 45, 99, "2026-05-27")
        XCTAssertNil(RepHistory.newBest(after: other, exercise: bench, rows: history() + [other]))
    }

    func test_newBest_heaviest_yet_is_separate_and_fires_once() {
        var rows = history()
        let first = row(bench, 55, 3, "2026-05-27")
        XCTAssertEqual(
            RepHistory.newBest(after: first, exercise: bench, rows: rows + [first]),
            .heaviest(weightLb: 55, previousLb: 50, previousDayKey: "2026-05-18"))
        rows.append(first)
        let second = row(bench, 55, 3, "2026-05-27", hour: 13)
        XCTAssertNil(RepHistory.newBest(after: second, exercise: bench, rows: rows + [second]))
    }

    func test_newBest_heaviest_needs_an_earlier_weighted_day() {
        let bodyweightOnly = [row(bench, nil, 10, "2026-05-18"), row(bench, nil, 10, "2026-05-20")]
        let r = row(bench, 10, 5, "2026-05-27")
        XCTAssertNil(RepHistory.newBest(after: r, exercise: bench, rows: bodyweightOnly + [r]))
    }

    func test_newBest_never_fires_for_a_back_filled_row() {
        let backfill = row(bench, 50, 99, "2026-05-19")   // history already has 05-20
        XCTAssertNil(RepHistory.newBest(after: backfill, exercise: bench, rows: history() + [backfill]))
    }

    func test_newBest_for_a_fixed_load_after_the_weight_is_edited() {
        // Stamped at 30 lb in May; the baby is 32 lb now. A new weight is "heaviest yet", not reps-at-weight.
        let rows = [row(baby, 30, 20, "2026-05-18"), row(baby, 30, 24, "2026-05-20")]
        let r = row(baby, 32, 1, "2026-05-27")
        XCTAssertEqual(
            RepHistory.newBest(after: r, exercise: baby, rows: rows + [r]),
            .heaviest(weightLb: 32, previousLb: 30, previousDayKey: "2026-05-18"))
    }

    func test_newBest_longest_hold() {
        let rows = [row(plank, nil, 1, "2026-05-18", hold: 40), row(plank, nil, 1, "2026-05-20", hold: 50)]
        let short = row(plank, nil, 1, "2026-05-27", hold: 45)
        XCTAssertNil(RepHistory.newBest(after: short, exercise: plank, rows: rows + [short]))
        let long = row(plank, nil, 1, "2026-05-27", hour: 13, hold: 55)
        XCTAssertEqual(
            RepHistory.newBest(after: long, exercise: plank, rows: rows + [short, long]),
            .longestHold(seconds: 55, previousSeconds: 50, previousDayKey: "2026-05-20"))
    }

    func test_newBest_most_minutes_at_a_weight() {
        let rows = [row(carry, 30, 10, "2026-05-18"), row(carry, 30, 12, "2026-05-20")]
        let r = row(carry, 30, 15, "2026-05-27")
        XCTAssertEqual(
            RepHistory.newBest(after: r, exercise: carry, rows: rows + [r]),
            .atWeight(measure: .minutes, weight: .init(30), amount: 15, previousBest: 12, previousDayKey: "2026-05-20"))
    }

    // MARK: - Weekly reps and notes

    private func exercises() -> [ExerciseDTO] { [bench, pushups, plank, carry] }

    /// One bodyweight push-up row of `reps` in the ISO week `weeksAgo` before `now`'s (a Wednesday).
    private func week(_ reps: Int, weeksAgo: Int, ex: ExerciseDTO? = nil) -> WorkoutSetDTO {
        let wed = Dates.isoCalendar.date(byAdding: .day, value: -7 * weeksAgo, to: now)!
        return WorkoutSetDTO(userId: uid, exerciseId: (ex ?? pushups).id, reps: reps, timestamp: wed)
    }

    private func weekly(_ rows: [WorkoutSetDTO]) -> RepHistory.WeeklyReps {
        RepHistory.weeklyReps(sets: rows, exercises: exercises(), now: now)
    }

    func test_weekly_totals_this_vs_last_and_only_rep_exercises() {
        let w = weekly([week(40, weeksAgo: 0), week(60, weeksAgo: 1),
                        week(1, weeksAgo: 0, ex: plank), week(30, weeksAgo: 0, ex: carry)])
        XCTAssertEqual(w.thisWeek, 40)
        XCTAssertEqual(w.lastWeek, 60)
        XCTAssertEqual(w.delta, -20)
    }

    func test_weekly_note_approaching_at_the_75_percent_edge() {
        XCTAssertEqual(weekly([week(75, weeksAgo: 0), week(100, weeksAgo: 1)]).note, .approaching(remaining: 25))
        XCTAssertEqual(weekly([week(74, weeksAgo: 0), week(100, weeksAgo: 1)]).note, .none)
        XCTAssertEqual(weekly([week(99, weeksAgo: 0), week(100, weeksAgo: 1)]).note, .approaching(remaining: 1))
    }

    func test_weekly_note_matching_last_week_exactly_is_quiet() {
        XCTAssertEqual(weekly([week(100, weeksAgo: 0), week(100, weeksAgo: 1)]).note, .none)
    }

    func test_weekly_note_passed() {
        XCTAssertEqual(weekly([week(135, weeksAgo: 0), week(100, weeksAgo: 1)]).note, .passed(by: 35))
    }

    func test_weekly_note_best_week_needs_three_earlier_logged_weeks() {
        let two = [week(100, weeksAgo: 1), week(90, weeksAgo: 2), week(150, weeksAgo: 0)]
        XCTAssertEqual(weekly(two).note, .passed(by: 50), "only 2 earlier weeks: not enough for 'best'")
        let three = two + [week(80, weeksAgo: 3)]
        XCTAssertEqual(weekly(three).note, .bestWeek)
        let notBest = [week(100, weeksAgo: 1), week(90, weeksAgo: 2), week(200, weeksAgo: 3), week(150, weeksAgo: 0)]
        XCTAssertEqual(weekly(notBest).note, .passed(by: 50))
    }

    func test_weekly_note_first_week_back_after_a_gap_has_no_comparison() {
        // Logged 3 and 4 weeks ago, nothing last week or the week before, back this week.
        let w = weekly([week(80, weeksAgo: 4), week(80, weeksAgo: 3), week(10, weeksAgo: 0)])
        XCTAssertEqual(w.note, .firstWeekBack)
        XCTAssertEqual(w.lastWeek, 0)
    }

    func test_weekly_note_none_for_a_brand_new_history_or_an_empty_week() {
        XCTAssertEqual(weekly([week(10, weeksAgo: 0)]).note, .none, "first week ever: nothing to compare or welcome back")
        XCTAssertEqual(weekly([week(100, weeksAgo: 1)]).note, .none, "nothing logged this week yet")
        XCTAssertEqual(weekly([]).note, .none)
    }

    func test_weekly_breakdown_this_week_most_reps_first() {
        let w = weekly([week(10, weeksAgo: 0), week(30, weeksAgo: 0, ex: bench), week(25, weeksAgo: 1),
                        week(1, weeksAgo: 0, ex: plank)])
        XCTAssertEqual(w.byExercise.map(\.exerciseId), ["bench", "pushups"])
        XCTAssertEqual(w.byExercise.map(\.reps), [30, 10])
    }

    func test_weekly_announcement_fires_once_per_kind_per_week() {
        let passed = weekly([week(135, weeksAgo: 0), week(100, weeksAgo: 1)])
        let first = RepHistory.weeklyNoteAnnouncement(passed, now: now, stored: "")
        XCTAssertEqual(first, "2026-05-25|passed")
        XCTAssertNil(RepHistory.weeklyNoteAnnouncement(passed, now: now, stored: first!), "already announced this week")
        // A different kind in the same week still announces, and both are remembered.
        let approaching = weekly([week(80, weeksAgo: 0), week(100, weeksAgo: 1)])
        let second = RepHistory.weeklyNoteAnnouncement(approaching, now: now, stored: first!)
        XCTAssertEqual(second, "2026-05-25|passed,approaching")
        XCTAssertNil(RepHistory.weeklyNoteAnnouncement(approaching, now: now, stored: second!))
    }

    func test_weekly_announcement_resets_in_a_new_week_and_ignores_no_note() {
        let passed = weekly([week(135, weeksAgo: 0), week(100, weeksAgo: 1)])
        let nextMonday = ts("2026-06-01")
        XCTAssertEqual(RepHistory.weeklyNoteAnnouncement(passed, now: nextMonday, stored: "2026-05-25|passed"),
                       "2026-06-01|passed")
        XCTAssertNil(RepHistory.weeklyNoteAnnouncement(weekly([]), now: now, stored: ""))
        XCTAssertNil(RepHistory.weeklyNoteAnnouncement(weekly([week(100, weeksAgo: 0), week(100, weeksAgo: 1)]),
                                                       now: now, stored: ""), "matching exactly: no note")
    }

    // MARK: - Canonical weight

    func test_weight_key_treats_a_unit_round_trip_as_the_same_weight() {
        // 22.68 kg typed back in is 50.000841 lb; 50 lb to kg and back is 49.99999999.
        XCTAssertEqual(RepHistory.WeightKey(50.000841062424), RepHistory.WeightKey(50))
        XCTAssertEqual(RepHistory.WeightKey(49.999999998893784), RepHistory.WeightKey(50))
        XCTAssertEqual(RepHistory.WeightKey(50.000841062424).lb, 50)
        XCTAssertNotEqual(RepHistory.WeightKey(52.5), RepHistory.WeightKey(52.51))
        XCTAssertNotEqual(RepHistory.WeightKey(50), RepHistory.WeightKey(52.5))
        XCTAssertEqual(RepHistory.WeightKey(0.004), .bodyweight, "below the precision floor is no weight")
        XCTAssertEqual(RepHistory.WeightKey(.nan), .bodyweight)
    }

    func test_days_fold_one_displayed_weight_into_one_line() {
        let rows = [row(bench, 50, 10, "2026-05-20"),
                    row(bench, 50.000841062424, 5, "2026-05-20", hour: 14)]
        let d = RepHistory.days(for: bench, rows: rows)[0]
        XCTAssertEqual(d.lines.count, 1)
        XCTAssertEqual(d.totalAmount, 15)
        XCTAssertEqual(RepHistory.summary(d, formatWeight: lb), "50 lb × 15")
    }

    func test_weekly_sunday_night_belongs_to_the_old_week() {
        // now = Mon 2026-06-01 00:30Z-ish would be TZ-fragile; use noon Sunday vs Monday instead.
        let sunday = WorkoutSetDTO(userId: uid, exerciseId: "pushups", reps: 20, timestamp: ts("2026-05-24"))
        let monday = WorkoutSetDTO(userId: uid, exerciseId: "pushups", reps: 5, timestamp: ts("2026-05-25"))
        let w = weekly([sunday, monday])
        XCTAssertEqual(w.thisWeek, 5)
        XCTAssertEqual(w.lastWeek, 20)
    }

    func test_note_text() {
        XCTAssertEqual(RepHistory.noteText(.approaching(remaining: 40)), "40 reps to match last week")
        XCTAssertEqual(RepHistory.noteText(.approaching(remaining: 1)), "1 rep to match last week")
        XCTAssertEqual(RepHistory.noteText(.passed(by: 35)), "+35 reps vs last week")
        XCTAssertEqual(RepHistory.noteText(.bestWeek), "Most reps in a week yet")
        XCTAssertEqual(RepHistory.noteText(.firstWeekBack), "First week back")
        XCTAssertNil(RepHistory.noteText(.none))
    }

    // MARK: - Summary formatting

    func test_summary_reads_alike_for_every_shape() {
        let weighted = RepHistory.days(for: bench, rows: [row(bench, 50, 30, "2026-05-20"), row(bench, 55, 8, "2026-05-20", hour: 13)])[0]
        XCTAssertEqual(RepHistory.summary(weighted, formatWeight: lb), "50 lb × 30 · 55 lb × 8")
        let body = RepHistory.days(for: pushups, rows: [row(pushups, nil, 42, "2026-05-20")])[0]
        XCTAssertEqual(RepHistory.summary(body, formatWeight: lb), "42 reps")
        let one = RepHistory.days(for: pushups, rows: [row(pushups, nil, 1, "2026-05-20")])[0]
        XCTAssertEqual(RepHistory.summary(one, formatWeight: lb), "1 rep")
        let mixed = RepHistory.days(for: bench, rows: [row(bench, nil, 12, "2026-05-20"), row(bench, 25, 8, "2026-05-20", hour: 13)])[0]
        XCTAssertEqual(RepHistory.summary(mixed, formatWeight: lb), "bodyweight × 12 · 25 lb × 8")
        let fractional = RepHistory.days(for: bench, rows: [row(bench, 52.5, 6, "2026-05-20")])[0]
        XCTAssertEqual(RepHistory.summary(fractional, formatWeight: lb), "52.5 lb × 6")
        let single = RepHistory.days(for: plank, rows: [row(plank, nil, 1, "2026-05-20", hold: 50)])[0]
        XCTAssertEqual(RepHistory.summary(single, formatWeight: lb), "50 s")
    }

    func test_duration_text() {
        XCTAssertEqual(RepHistory.durationText(seconds: 50), "50 s")
        XCTAssertEqual(RepHistory.durationText(seconds: 120), "2 min")
        XCTAssertEqual(RepHistory.durationText(seconds: 130), "2 min 10 s")
    }
}
