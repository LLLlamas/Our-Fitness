import XCTest

// The phone<->watch wire format (`Shared/WatchSyncPayload.swift`), compiled
// straight into this target the same way `OurFitness/Domain` is — no
// `@testable import`, no SwiftData, no SwiftUI.
//
// WHY THIS FILE EXISTS: the phone and the watch are separate binaries that can
// briefly run DIFFERENT builds (the watch app updates on its own schedule). A
// wire-format mistake therefore doesn't fail loudly at compile time — it strands
// a user with a blank or crashing watch until they reinstall. These tests pin
// the format's encode/decode contract and, more importantly, document exactly
// which fields survive a payload from an older phone build and which do not.
//
// Every date is pinned (never a bare Date() — see CLAUDE.md CI rules). JSON's
// default date strategy is `.deferredToDate`, i.e. a Double of seconds since the
// 2001 reference date, which round-trips a pinned value exactly; the
// hand-written JSON below therefore interpolates
// `timeIntervalSinceReferenceDate` rather than hardcoding a magic number.
final class WatchSyncPayloadTests: XCTestCase {

    // 2026-06-03 12:00:00 UTC — the project's standard fixed clock.
    private let now = Date(timeIntervalSince1970: 1_780_488_000)

    /// `now` shifted by whole days, for fixtures that need distinct instants.
    private func offsetDays(_ days: Int) -> Date {
        now.addingTimeInterval(TimeInterval(days) * 86_400)
    }

    private let profileId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let reminderId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let groupId = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!

    private func makeEncoder() -> JSONEncoder { JSONEncoder() }
    private func makeDecoder() -> JSONDecoder { JSONDecoder() }

    // MARK: - Fixtures

    /// An envelope with EVERY field populated — no nils, no empty arrays, a
    /// running live session — so the round-trip test can't pass by accident on
    /// fields that happen to be at their defaults.
    private func fullyPopulatedEnvelope() -> WatchSnapshotEnvelope {
        WatchSnapshotEnvelope(
            schemaVersion: WatchSnapshotEnvelope.currentSchemaVersion,
            profileId: profileId,
            profileName: "Sam",
            mode: "reset", // Circuit's raw value, per the back-compat note in CLAUDE.md
            bodyWeightLb: 163.4,
            reminders: [
                ReminderSnapshot(
                    id: reminderId,
                    groupId: groupId,
                    groupName: "Plants",
                    groupKind: "plants",
                    name: "Monstera",
                    speciesId: "monstera-deliciosa",
                    room: "Living room",
                    lightRaw: "bright-indirect",
                    potDiameterInches: 10,
                    intervalDays: 7,
                    amountFlOz: 16,
                    createdAt: offsetDays(-30),
                    snoozedUntil: offsetDays(1),
                    lastDoneAt: offsetDays(-4),
                    notes: "Let the top inch dry out.",
                    preferredHour: 8
                ),
                ReminderSnapshot(
                    id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
                    groupId: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
                    groupName: "Home",
                    groupKind: "custom",
                    name: "Replace filter",
                    intervalDays: 90,
                    createdAt: offsetDays(-120)
                )
            ],
            today: TodaySnapshot(
                caloriesConsumed: 1_420, caloriesTarget: 2_100,
                proteinG: 118, proteinTargetG: 165,
                carbsG: 140, carbsTargetG: 210,
                fatG: 47, fatTargetG: 70,
                steps: 7_318, stepsGoal: 10_000,
                waterFlOz: 48, waterGoalFlOz: 96,
                waterLastFlOz: 16
            ),
            quickLogExercises: [
                QuickLogExercise(id: "lifted-baby", name: "Lifted Baby",
                                 kind: "reps", loadLb: 30, loggedToday: 12),
                QuickLogExercise(id: "carried-baby", name: "Carried Baby",
                                 kind: "duration", loadLb: 30, loggedToday: 2)
            ],
            mealShortcuts: [
                MealShortcut(id: "tmpl-breakfast", name: "Usual breakfast", emoji: "🍳",
                             calories: 520, proteinG: 34, source: "template"),
                MealShortcut(id: "food-1234", name: "Greek yogurt",
                             calories: 130, proteinG: 17, source: "recent")
            ],
            liveSession: LiveSessionSnapshot(
                startDate: now.addingTimeInterval(-900),
                activityId: "stroller-walk",
                activityName: "Stroller walk",
                met: 4.5,
                expectedMinutes: 30
            ),
            generatedAt: now
        )
    }

    /// The MINIMUM JSON that decodes — i.e. every key that is genuinely required
    /// (see `test_decode_throws_when_any_nonOptional_envelope_key_is_missing`).
    /// Optional keys are deliberately absent, standing in for a payload written
    /// by an older phone build that didn't know about them yet.
    private func minimalEnvelopeJSON() -> Data {
        let seconds = now.timeIntervalSinceReferenceDate
        let json = """
        {
          "schemaVersion": 1,
          "profileId": "\(profileId.uuidString)",
          "mode": "build",
          "bodyWeightLb": 180.5,
          "reminders": [
            {
              "id": "\(reminderId.uuidString)",
              "groupId": "\(groupId.uuidString)",
              "groupName": "Plants",
              "groupKind": "plants",
              "name": "Fiddle Leaf Fig",
              "intervalDays": 10,
              "createdAt": \(seconds)
            }
          ],
          "today": {
            "caloriesConsumed": 900, "caloriesTarget": 2600,
            "proteinG": 60, "proteinTargetG": 180,
            "carbsG": 80, "carbsTargetG": 300,
            "fatG": 30, "fatTargetG": 80,
            "steps": 4000, "stepsGoal": 8000,
            "waterFlOz": 24, "waterGoalFlOz": 80
          },
          "quickLogExercises": [],
          "mealShortcuts": [],
          "generatedAt": \(seconds)
        }
        """
        return Data(json.utf8)
    }

    // MARK: - Envelope round-trip

    func test_envelope_roundTrips_with_every_field_populated() throws {
        let original = fullyPopulatedEnvelope()
        let data = try makeEncoder().encode(original)
        let decoded = try makeDecoder().decode(WatchSnapshotEnvelope.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_envelope_roundTrips_at_its_defaults() throws {
        // The other end of the range: no profile name, no live session, every
        // collection empty — what the phone sends for a brand-new profile.
        let original = WatchSnapshotEnvelope(
            profileId: profileId, mode: "build", bodyWeightLb: 200, generatedAt: now
        )
        let data = try makeEncoder().encode(original)
        let decoded = try makeDecoder().decode(WatchSnapshotEnvelope.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertNil(decoded.liveSession)
        XCTAssertTrue(decoded.reminders.isEmpty)
    }

    func test_envelope_dates_roundTrip_exactly() throws {
        // Guards the `.deferredToDate` assumption the rest of this file rests
        // on: a pinned Date must come back bit-for-bit, not rounded to a second.
        let generatedAt = now.addingTimeInterval(0.25)
        let original = WatchSnapshotEnvelope(
            profileId: profileId, mode: "build", bodyWeightLb: 200, generatedAt: generatedAt
        )
        let data = try makeEncoder().encode(original)
        let decoded = try makeDecoder().decode(WatchSnapshotEnvelope.self, from: data)
        XCTAssertEqual(decoded.generatedAt.timeIntervalSinceReferenceDate,
                       generatedAt.timeIntervalSinceReferenceDate,
                       accuracy: 0.000_001)
    }

    // MARK: - WatchAction round-trip (all nine cases)

    func test_watchAction_roundTrips_for_every_case() throws {
        let encoder = makeEncoder()
        let decoder = makeDecoder()

        // One entry per case of `WatchAction`. If a case is added and this array
        // isn't extended, the count assertion below fails and says so.
        let actions: [(label: String, action: WatchAction)] = [
            ("done", .done(reminderId: reminderId, date: now)),
            ("setInterval", .setInterval(reminderId: reminderId, days: 14)),
            ("snooze", .snooze(reminderId: reminderId)),
            ("logWater", .logWater(flOz: 16.5, date: now)),
            ("logQuickSet", .logQuickSet(exerciseId: "lifted-baby", amount: 3, date: now)),
            ("undoQuickSet", .undoQuickSet(exerciseId: "lifted-baby", date: now)),
            ("logMeal", .logMeal(shortcutId: "tmpl-breakfast", source: "template",
                                 slot: "breakfast", date: now)),
            ("startLiveSession", .startLiveSession(
                activityId: "stroller-walk", activityName: "Stroller walk",
                met: 4.5, expectedMinutes: 30, startDate: now)),
            ("endLiveSession", .endLiveSession(startDate: now, elapsedSeconds: 1_805))
        ]

        XCTAssertEqual(actions.count, 9, "WatchAction gained or lost a case — cover it here.")

        for (label, action) in actions {
            let data = try encoder.encode(action)
            let decoded = try decoder.decode(WatchAction.self, from: data)
            XCTAssertEqual(decoded, action, "\(label) did not survive the round trip")
        }
    }

    func test_watchAction_dayScoped_date_survives_an_offline_queue() throws {
        // `transferUserInfo` can deliver days later; the write must land on the
        // day the action was TAKEN. That only holds if the date rides along
        // intact, so assert the value itself, not just equality of the case.
        let takenOn = offsetDays(-3)
        let data = try makeEncoder().encode(WatchAction.done(reminderId: reminderId, date: takenOn))
        let decoded = try makeDecoder().decode(WatchAction.self, from: data)

        guard case let .done(decodedId, decodedDate) = decoded else {
            return XCTFail("expected .done, got \(decoded)")
        }
        XCTAssertEqual(decodedId, reminderId)
        XCTAssertEqual(decodedDate.timeIntervalSinceReferenceDate,
                       takenOn.timeIntervalSinceReferenceDate,
                       accuracy: 0.000_001)
    }

    // MARK: - Forward / backward compatibility
    //
    // These tests DOCUMENT the real behaviour of Swift's synthesised `Codable`,
    // which is not what the type's defaulted initialiser suggests: a default
    // value in `init` is NOT applied when a JSON key is missing. Only OPTIONAL
    // properties decode as absent; every non-optional property is required on
    // the wire regardless of its `init` default.

    func test_decode_tolerates_a_payload_missing_every_optional_field() throws {
        // Stand-in for an older phone build: only the required keys are present.
        let decoded = try makeDecoder().decode(WatchSnapshotEnvelope.self,
                                               from: minimalEnvelopeJSON())

        // Optional envelope fields come back nil rather than throwing.
        XCTAssertNil(decoded.profileName)
        XCTAssertNil(decoded.liveSession)

        // Optional nested fields likewise.
        XCTAssertNil(decoded.today.waterLastFlOz)
        let reminder = try XCTUnwrap(decoded.reminders.first)
        XCTAssertNil(reminder.speciesId)
        XCTAssertNil(reminder.room)
        XCTAssertNil(reminder.lightRaw)
        XCTAssertNil(reminder.potDiameterInches)
        XCTAssertNil(reminder.amountFlOz)
        XCTAssertNil(reminder.snoozedUntil)
        XCTAssertNil(reminder.lastDoneAt)
        XCTAssertNil(reminder.notes)
        XCTAssertNil(reminder.preferredHour)

        // The required fields that were present decoded correctly.
        XCTAssertEqual(decoded.profileId, profileId)
        XCTAssertEqual(decoded.mode, "build")
        XCTAssertEqual(decoded.bodyWeightLb, 180.5, accuracy: 0.000_001)
        XCTAssertEqual(reminder.name, "Fiddle Leaf Fig")
        XCTAssertEqual(reminder.intervalDays, 10)
        XCTAssertTrue(decoded.quickLogExercises.isEmpty)
        XCTAssertTrue(decoded.mealShortcuts.isEmpty)
    }

    func test_decode_ignores_unknown_keys_from_a_newer_phone_build() throws {
        // The opposite direction: a NEWER phone sends fields this watch build
        // has never heard of. Extra keys must be skipped, not rejected.
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: minimalEnvelopeJSON()) as? [String: Any]
        )
        object["someFieldFromTheFuture"] = 42
        object["anotherOne"] = ["nested": true]
        let data = try JSONSerialization.data(withJSONObject: object)

        let decoded = try makeDecoder().decode(WatchSnapshotEnvelope.self, from: data)
        XCTAssertEqual(decoded.profileId, profileId)
    }

    func test_decode_tolerates_any_missing_key_except_profileId() throws {
        // The envelope hand-writes init(from:) precisely so this holds. Synthesised
        // Codable would throw on every one of these, and a phone build that
        // omitted, say, `mealShortcuts` would cost the watch its REMINDERS too —
        // the whole envelope fails, not just the unknown section. profileId is the
        // sole genuinely-required key: there is no safe default for identity.
        let defaultable = [
            "schemaVersion", "mode", "bodyWeightLb",
            "reminders", "today", "quickLogExercises", "mealShortcuts", "generatedAt"
        ]
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: minimalEnvelopeJSON()) as? [String: Any]
        )

        for key in defaultable {
            var truncated = object
            XCTAssertNotNil(truncated.removeValue(forKey: key),
                            "\(key) was not in the minimal payload — fixture drifted")
            let data = try JSONSerialization.data(withJSONObject: truncated)
            XCTAssertNoThrow(
                try makeDecoder().decode(WatchSnapshotEnvelope.self, from: data),
                "omitting \(key) broke decoding — an older phone would strand the watch"
            )
        }

        var withoutId = object
        withoutId.removeValue(forKey: "profileId")
        XCTAssertThrowsError(
            try makeDecoder().decode(
                WatchSnapshotEnvelope.self,
                from: try JSONSerialization.data(withJSONObject: withoutId)
            ),
            "profileId must stay required — an envelope with no identity is meaningless"
        )
    }

    func test_missing_keys_fall_back_to_documented_defaults() throws {
        // Not just "doesn't throw" — the values have to be the sane ones, since
        // the watch renders them straight onto the screen.
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: minimalEnvelopeJSON()) as? [String: Any]
        )
        var stripped = object
        for key in ["schemaVersion", "mode", "bodyWeightLb", "reminders",
                    "today", "quickLogExercises", "mealShortcuts", "generatedAt"] {
            stripped.removeValue(forKey: key)
        }
        let decoded = try makeDecoder().decode(
            WatchSnapshotEnvelope.self,
            from: try JSONSerialization.data(withJSONObject: stripped)
        )

        XCTAssertEqual(decoded.profileId, profileId)
        // Absent version means a payload predating versioning.
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertTrue(decoded.isReadable)
        XCTAssertEqual(decoded.mode, "")
        XCTAssertEqual(decoded.bodyWeightLb, 0)
        XCTAssertTrue(decoded.reminders.isEmpty)
        XCTAssertTrue(decoded.quickLogExercises.isEmpty)
        XCTAssertTrue(decoded.mealShortcuts.isEmpty)
        XCTAssertNil(decoded.liveSession)
        XCTAssertEqual(decoded.today, TodaySnapshot())
        XCTAssertEqual(decoded.generatedAt, .distantPast)
    }

    func test_decode_tolerates_any_missing_today_key() throws {
        // TodaySnapshot hand-writes init(from:) for the same reason the envelope
        // does. This is the test that catches someone adding a thirteenth metric
        // as a plain non-optional and silently breaking every older payload.
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: minimalEnvelopeJSON()) as? [String: Any]
        )
        let today = try XCTUnwrap(object["today"] as? [String: Any])

        for key in today.keys.sorted() {
            var truncatedToday = today
            truncatedToday.removeValue(forKey: key)
            var envelope = object
            envelope["today"] = truncatedToday
            let data = try JSONSerialization.data(withJSONObject: envelope)
            XCTAssertNoThrow(
                try makeDecoder().decode(WatchSnapshotEnvelope.self, from: data),
                "omitting today.\(key) broke decoding"
            )
        }

        // A wholly empty today object still decodes, to all-zero.
        var envelope = object
        envelope["today"] = [String: Any]()
        let decoded = try makeDecoder().decode(
            WatchSnapshotEnvelope.self,
            from: try JSONSerialization.data(withJSONObject: envelope)
        )
        XCTAssertEqual(decoded.today, TodaySnapshot())
    }

    // MARK: - Schema version

    func test_isReadable_at_and_below_currentSchemaVersion() {
        for version in [WatchSnapshotEnvelope.currentSchemaVersion,
                        WatchSnapshotEnvelope.currentSchemaVersion - 1] {
            let envelope = WatchSnapshotEnvelope(
                schemaVersion: version, profileId: profileId,
                mode: "build", bodyWeightLb: 180, generatedAt: now
            )
            XCTAssertTrue(envelope.isReadable, "version \(version) should be readable")
        }
    }

    func test_isReadable_false_above_currentSchemaVersion() {
        let envelope = WatchSnapshotEnvelope(
            schemaVersion: WatchSnapshotEnvelope.currentSchemaVersion + 1,
            profileId: profileId, mode: "build", bodyWeightLb: 180, generatedAt: now
        )
        XCTAssertFalse(envelope.isReadable)
    }

    func test_schemaVersion_defaults_to_current_when_unspecified() {
        let envelope = WatchSnapshotEnvelope(
            profileId: profileId, mode: "build", bodyWeightLb: 180, generatedAt: now
        )
        XCTAssertEqual(envelope.schemaVersion, WatchSnapshotEnvelope.currentSchemaVersion)
        XCTAssertTrue(envelope.isReadable)
    }

    func test_schemaVersion_survives_the_round_trip_unchanged() throws {
        // An unreadable envelope must still DECODE — that's how the watch learns
        // it should keep its last good cache instead of rendering garbage.
        let future = WatchSnapshotEnvelope(
            schemaVersion: WatchSnapshotEnvelope.currentSchemaVersion + 1,
            profileId: profileId, mode: "build", bodyWeightLb: 180, generatedAt: now
        )
        let data = try makeEncoder().encode(future)
        let decoded = try makeDecoder().decode(WatchSnapshotEnvelope.self, from: data)
        XCTAssertEqual(decoded.schemaVersion, WatchSnapshotEnvelope.currentSchemaVersion + 1)
        XCTAssertFalse(decoded.isReadable)
    }

    // MARK: - ReminderSnapshot.isPlant

    private func snapshot(groupKind: String) -> ReminderSnapshot {
        ReminderSnapshot(
            id: reminderId, groupId: groupId, groupName: "Group",
            groupKind: groupKind, name: "Thing", intervalDays: 7, createdAt: now
        )
    }

    func test_isPlant_true_only_for_the_plants_groupKind() {
        XCTAssertTrue(snapshot(groupKind: "plants").isPlant)
        // The wire side answers by raw group kind alone — unlike ReminderDTO,
        // there is no speciesId involved — so anything else is false.
        XCTAssertFalse(snapshot(groupKind: "custom").isPlant)
        XCTAssertFalse(snapshot(groupKind: "").isPlant)
        XCTAssertFalse(snapshot(groupKind: "Plants").isPlant, "raw values are case-sensitive")
        XCTAssertFalse(snapshot(groupKind: "plant").isPlant)
    }

    func test_isPlant_survives_the_round_trip() throws {
        let original = snapshot(groupKind: "plants")
        let data = try makeEncoder().encode(original)
        let decoded = try makeDecoder().decode(ReminderSnapshot.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertTrue(decoded.isPlant)
    }

    // MARK: - QuickLogExercise.isDuration

    func test_isDuration_true_only_for_the_duration_kind() {
        func exercise(kind: String) -> QuickLogExercise {
            QuickLogExercise(id: "e", name: "Exercise", kind: kind)
        }
        XCTAssertTrue(exercise(kind: "duration").isDuration)
        XCTAssertFalse(exercise(kind: "reps").isDuration)
        XCTAssertFalse(exercise(kind: "").isDuration)
        XCTAssertFalse(exercise(kind: "Duration").isDuration, "raw values are case-sensitive")
    }

    func test_quickLogExercise_roundTrips_and_keeps_isDuration() throws {
        let original = QuickLogExercise(id: "carried-baby", name: "Carried Baby",
                                        kind: "duration", loadLb: 30, loggedToday: 4)
        let data = try makeEncoder().encode(original)
        let decoded = try makeDecoder().decode(QuickLogExercise.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertTrue(decoded.isDuration)
    }

    // MARK: - Transport keys

    func test_syncKeys_are_stable() {
        // These strings are the contract with an ALREADY-INSTALLED watch build;
        // renaming one silently breaks sync for anyone mid-update.
        XCTAssertEqual(WatchSyncKeys.snapshotContextKey, "reminderSnapshots")
        XCTAssertEqual(WatchSyncKeys.actionUserInfoKey, "watchAction")
        XCTAssertEqual(WatchSyncKeys.thumbnailFilePrefix, "plant-thumb-")
    }
}
