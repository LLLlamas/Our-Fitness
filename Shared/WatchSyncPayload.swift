// Shared wire format between the OurFitness app (source of truth, SwiftData)
// and the OurFitnessWatch companion app (thin client, no local store).
//
// Compiled into BOTH targets — the ONE file in both targets' `sources:` in
// project.yml, alongside Shared/LiveSessionAttributes.swift. Kept to plain
// Foundation types only (no SwiftData, no WatchConnectivity) so it carries
// zero framework weight into the watch target.
//
// Transport: the phone pushes ONE `WatchSnapshotEnvelope` via
// `WCSession.updateApplicationContext` (latest-wins, delivered even when the
// watch app isn't foregrounded) under `WatchSyncKeys.snapshotContextKey`. The
// watch sends a `WatchAction` back via `WCSession.transferUserInfo` (queues
// automatically while unreachable, so a wrist action taken offline is never
// lost) under `WatchSyncKeys.actionUserInfoKey`. Photo thumbnails travel
// separately via `transferFile`, keyed by reminder id in the file's metadata —
// `updateApplicationContext`'s payload is small, so images don't ride along.
//
// WHY ONE ENVELOPE, NOT A KEY PER FEATURE: `updateApplicationContext` REPLACES
// the entire context dictionary. Two features each pushing their own key would
// silently clobber each other, and the loser would look like a sync bug rather
// than a lost write. Everything the watch needs therefore travels together, and
// the phone always builds the whole envelope in one pass.

import Foundation

/// A read-only projection of one reminder for the watch's list/detail UI.
/// `groupKind` is the raw string of `ReminderGroupKind` ("plants"/"custom") —
/// this file intentionally doesn't depend on the Domain module's enum so it
/// stays a zero-dependency wire format compiled identically into both targets.
public struct ReminderSnapshot: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var groupId: UUID
    public var groupName: String
    public var groupKind: String
    public var name: String
    public var speciesId: String?
    public var room: String?
    public var lightRaw: String?
    public var potDiameterInches: Int?
    public var intervalDays: Int
    public var amountFlOz: Double?
    public var createdAt: Date
    public var snoozedUntil: Date?
    public var lastDoneAt: Date?
    public var notes: String?
    /// The profile's preferred notification hour (0-23), so the watch's
    /// optimistic snooze lands on the same time the phone will schedule
    /// rather than assuming `ReminderSchedule.defaultReminderHour`.
    public var preferredHour: Int?

    /// Every field added after the initial wire format is optional with a
    /// `nil` default, so a payload encoded by an older build still decodes.
    public init(
        id: UUID, groupId: UUID, groupName: String, groupKind: String, name: String,
        speciesId: String? = nil, room: String? = nil, lightRaw: String? = nil,
        potDiameterInches: Int? = nil, intervalDays: Int, amountFlOz: Double? = nil,
        createdAt: Date, snoozedUntil: Date? = nil, lastDoneAt: Date? = nil,
        notes: String? = nil, preferredHour: Int? = nil
    ) {
        self.id = id
        self.groupId = groupId
        self.groupName = groupName
        self.groupKind = groupKind
        self.name = name
        self.speciesId = speciesId
        self.room = room
        self.lightRaw = lightRaw
        self.potDiameterInches = potDiameterInches
        self.intervalDays = intervalDays
        self.amountFlOz = amountFlOz
        self.createdAt = createdAt
        self.snoozedUntil = snoozedUntil
        self.lastDoneAt = lastDoneAt
        self.notes = notes
        self.preferredHour = preferredHour
    }

    public var isPlant: Bool { groupKind == "plants" }
}

// MARK: - Today

/// The glanceable numbers for the watch's Today screen. Every value is FINISHED
/// — the phone folds its SwiftData logs and sends results, so the watch needs
/// none of DailyTotals / MacroBudget / DailyBurn and no raw log arrays.
public struct TodaySnapshot: Codable, Equatable, Sendable {
    public var caloriesConsumed: Int
    public var caloriesTarget: Int
    public var proteinG: Int
    public var proteinTargetG: Int
    public var carbsG: Int
    public var carbsTargetG: Int
    public var fatG: Int
    public var fatTargetG: Int
    public var steps: Int
    public var stepsGoal: Int
    public var waterFlOz: Double
    public var waterGoalFlOz: Double
    /// Last amount logged, for the watch's tap-to-repeat button. Mirrors the
    /// phone's `AppStorage "waterLastFlOz.<profileId>"`, which WCSession can't see.
    public var waterLastFlOz: Double?

    public init(
        caloriesConsumed: Int = 0, caloriesTarget: Int = 0,
        proteinG: Int = 0, proteinTargetG: Int = 0,
        carbsG: Int = 0, carbsTargetG: Int = 0,
        fatG: Int = 0, fatTargetG: Int = 0,
        steps: Int = 0, stepsGoal: Int = 0,
        waterFlOz: Double = 0, waterGoalFlOz: Double = 0,
        waterLastFlOz: Double? = nil
    ) {
        self.caloriesConsumed = caloriesConsumed
        self.caloriesTarget = caloriesTarget
        self.proteinG = proteinG
        self.proteinTargetG = proteinTargetG
        self.carbsG = carbsG
        self.carbsTargetG = carbsTargetG
        self.fatG = fatG
        self.fatTargetG = fatTargetG
        self.steps = steps
        self.stepsGoal = stepsGoal
        self.waterFlOz = waterFlOz
        self.waterGoalFlOz = waterGoalFlOz
        self.waterLastFlOz = waterLastFlOz
    }

    /// Hand-written so a MISSING key falls back to the default instead of
    /// throwing. Swift's synthesised `Codable` ignores an `init` default for an
    /// absent key unless the property is Optional — so without this, adding a
    /// thirteenth metric here would break decoding of every payload written by
    /// an older phone, and the watch would lose the whole envelope (reminders
    /// included), not just the new number.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func int(_ key: CodingKeys) throws -> Int { try c.decodeIfPresent(Int.self, forKey: key) ?? 0 }
        func dbl(_ key: CodingKeys) throws -> Double { try c.decodeIfPresent(Double.self, forKey: key) ?? 0 }

        self.caloriesConsumed = try int(.caloriesConsumed)
        self.caloriesTarget = try int(.caloriesTarget)
        self.proteinG = try int(.proteinG)
        self.proteinTargetG = try int(.proteinTargetG)
        self.carbsG = try int(.carbsG)
        self.carbsTargetG = try int(.carbsTargetG)
        self.fatG = try int(.fatG)
        self.fatTargetG = try int(.fatTargetG)
        self.steps = try int(.steps)
        self.stepsGoal = try int(.stepsGoal)
        self.waterFlOz = try dbl(.waterFlOz)
        self.waterGoalFlOz = try dbl(.waterGoalFlOz)
        self.waterLastFlOz = try c.decodeIfPresent(Double.self, forKey: .waterLastFlOz)
    }
}

// MARK: - Quick log

/// One tap-to-+1 movement (the Circuit parenting exercises, plus any the user
/// added). `kind` is the raw string of `ExerciseKind` ("reps"/"duration") —
/// like `ReminderSnapshot.groupKind`, kept as a String so this file stays free
/// of Domain enums.
public struct QuickLogExercise: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var kind: String
    public var loadLb: Double?
    /// Count already logged today, so the watch can show progress without
    /// replaying the set history it doesn't have.
    public var loggedToday: Int

    public init(id: String, name: String, kind: String, loadLb: Double? = nil, loggedToday: Int = 0) {
        self.id = id
        self.name = name
        self.kind = kind
        self.loadLb = loadLb
        self.loggedToday = loggedToday
    }

    public var isDuration: Bool { kind == "duration" }
}

/// A one-tap meal the watch can log: a saved template or a frequently-logged
/// food, resolved phone-side. Macros ride along for display ONLY — when the
/// watch logs one, it sends `id` and the phone re-resolves the real numbers, so
/// a stale snapshot can never write wrong macros into the food log.
public struct MealShortcut: Codable, Equatable, Sendable, Identifiable {
    /// Stable id of the underlying template or food.
    public var id: String
    public var name: String
    public var emoji: String?
    public var calories: Int
    public var proteinG: Int
    /// Which list this came from: "template" or "recent".
    public var source: String

    public init(id: String, name: String, emoji: String? = nil,
                calories: Int, proteinG: Int, source: String) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.calories = calories
        self.proteinG = proteinG
        self.source = source
    }
}

/// The live session currently running, as the PHONE sees it. The phone owns
/// `LiveSessionStore`; the watch renders this and sends start/end actions
/// rather than keeping its own authoritative copy. Elapsed time is always
/// derived from `startDate`, so both devices agree with no clock sync.
public struct LiveSessionSnapshot: Codable, Equatable, Sendable {
    public var startDate: Date
    public var activityId: String
    public var activityName: String
    public var met: Double
    public var expectedMinutes: Int

    public init(startDate: Date, activityId: String, activityName: String,
                met: Double, expectedMinutes: Int) {
        self.startDate = startDate
        self.activityId = activityId
        self.activityName = activityName
        self.met = met
        self.expectedMinutes = expectedMinutes
    }
}

// MARK: - Envelope

/// Everything the watch needs, in one latest-wins push. See the file header for
/// why this is a single envelope rather than one context key per feature.
public struct WatchSnapshotEnvelope: Codable, Equatable, Sendable {
    /// Bumped only on a BREAKING change. A watch build that sees a version it
    /// doesn't know keeps its last good cache instead of decoding garbage;
    /// additive fields stay optional-with-default and don't bump this.
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var profileId: UUID
    public var profileName: String?
    /// Raw value of `Mode` — note this is "reset" for Circuit, per the
    /// back-compat note in CLAUDE.md.
    public var mode: String
    public var bodyWeightLb: Double
    public var reminders: [ReminderSnapshot]
    public var today: TodaySnapshot
    public var quickLogExercises: [QuickLogExercise]
    public var mealShortcuts: [MealShortcut]
    public var liveSession: LiveSessionSnapshot?
    public var generatedAt: Date

    public init(
        schemaVersion: Int = WatchSnapshotEnvelope.currentSchemaVersion,
        profileId: UUID,
        profileName: String? = nil,
        mode: String,
        bodyWeightLb: Double,
        reminders: [ReminderSnapshot] = [],
        today: TodaySnapshot = TodaySnapshot(),
        quickLogExercises: [QuickLogExercise] = [],
        mealShortcuts: [MealShortcut] = [],
        liveSession: LiveSessionSnapshot? = nil,
        generatedAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.profileId = profileId
        self.profileName = profileName
        self.mode = mode
        self.bodyWeightLb = bodyWeightLb
        self.reminders = reminders
        self.today = today
        self.quickLogExercises = quickLogExercises
        self.mealShortcuts = mealShortcuts
        self.liveSession = liveSession
        self.generatedAt = generatedAt
    }

    /// Hand-written for the same reason as `TodaySnapshot`'s: only the fields
    /// with no sensible default are genuinely required. Every collection and
    /// nested snapshot degrades to empty, so a payload from an older phone
    /// still yields a usable envelope rather than throwing and costing the
    /// watch its reminders too.
    ///
    /// Keep it this way. If you add a field here, give it a default in this
    /// initializer — do NOT rely on the memberwise default, which the
    /// synthesised decoder ignores.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Absent version means a payload predating versioning: treat as v1.
        self.schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        self.profileId = try c.decode(UUID.self, forKey: .profileId)
        self.profileName = try c.decodeIfPresent(String.self, forKey: .profileName)
        self.mode = try c.decodeIfPresent(String.self, forKey: .mode) ?? ""
        self.bodyWeightLb = try c.decodeIfPresent(Double.self, forKey: .bodyWeightLb) ?? 0
        self.reminders = try c.decodeIfPresent([ReminderSnapshot].self, forKey: .reminders) ?? []
        self.today = try c.decodeIfPresent(TodaySnapshot.self, forKey: .today) ?? TodaySnapshot()
        self.quickLogExercises = try c.decodeIfPresent([QuickLogExercise].self, forKey: .quickLogExercises) ?? []
        self.mealShortcuts = try c.decodeIfPresent([MealShortcut].self, forKey: .mealShortcuts) ?? []
        self.liveSession = try c.decodeIfPresent(LiveSessionSnapshot.self, forKey: .liveSession)
        self.generatedAt = try c.decodeIfPresent(Date.self, forKey: .generatedAt) ?? .distantPast
    }

    /// Whether this build can safely read the envelope. Older-but-known and
    /// equal versions decode fine (every added field defaults — see
    /// `init(from:)`); a NEWER major version means the phone changed the format
    /// under us, and the watch keeps its cached snapshot instead.
    public var isReadable: Bool { schemaVersion <= Self.currentSchemaVersion }
}

// MARK: - Wrist actions

/// A wrist-initiated mutation, sent phone-ward for the phone (source of
/// truth) to apply. The phone re-derives everything else (rescheduling the
/// notification, pushing a fresh snapshot back) — the watch never computes
/// due dates itself beyond display, even though it links `ReminderSchedule`
/// for that display math.
///
/// Every case carries a `date` where the write is day-scoped, so an action
/// queued offline lands on the day it was TAKEN, not the day it was delivered.
public enum WatchAction: Codable, Sendable, Equatable {
    case done(reminderId: UUID, date: Date)
    case setInterval(reminderId: UUID, days: Int)
    case snooze(reminderId: UUID)
    case logWater(flOz: Double, date: Date)
    case logQuickSet(exerciseId: String, amount: Int, date: Date)
    /// Removes the most recent set logged for this exercise on `date`.
    case undoQuickSet(exerciseId: String, date: Date)
    case logMeal(shortcutId: String, source: String, slot: String, date: Date)
    case startLiveSession(
        activityId: String, activityName: String, met: Double,
        expectedMinutes: Int, startDate: Date
    )
    case endLiveSession(startDate: Date, elapsedSeconds: Int)
}

public enum WatchSyncKeys {
    /// Key inside the `updateApplicationContext` dictionary; value is a
    /// JSON-encoded `WatchSnapshotEnvelope`.
    public static let snapshotContextKey = "reminderSnapshots"
    /// Key inside the `transferUserInfo` dictionary; value is JSON-encoded
    /// `WatchAction` `Data`.
    public static let actionUserInfoKey = "watchAction"
    /// Prefix for thumbnail file transfers; the reminder id travels in the
    /// transfer's `metadata`, not the filename (which is unique per transfer).
    public static let thumbnailFilePrefix = "plant-thumb-"
}
