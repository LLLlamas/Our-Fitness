// Shared wire format between the OurFitness app (source of truth, SwiftData)
// and the OurFitnessWatch companion app (thin client, no local store).
//
// Compiled into BOTH targets — the ONE file in both targets' `sources:` in
// project.yml, alongside Shared/LiveSessionAttributes.swift. Kept to plain
// Foundation types only (no SwiftData, no WatchConnectivity) so it carries
// zero framework weight into the watch target.
//
// Transport: the phone pushes the full reminder list via
// `WCSession.updateApplicationContext` (latest-wins, delivered even when the
// watch app isn't foregrounded) as JSON-encoded `[ReminderSnapshot]` under
// `WatchSyncKeys.snapshotContextKey`. The watch sends a `WatchAction` back via
// `WCSession.transferUserInfo` (queues automatically while unreachable, so a
// wrist action taken offline is never lost) as JSON-encoded data under
// `WatchSyncKeys.actionUserInfoKey`. Photo thumbnails travel separately via
// `transferFile`, keyed by reminder id in the file's last path component —
// `updateApplicationContext`'s payload is small, so images don't ride along.

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

    public init(
        id: UUID, groupId: UUID, groupName: String, groupKind: String, name: String,
        speciesId: String? = nil, room: String? = nil, lightRaw: String? = nil,
        potDiameterInches: Int? = nil, intervalDays: Int, amountFlOz: Double? = nil,
        createdAt: Date, snoozedUntil: Date? = nil, lastDoneAt: Date? = nil
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
    }

    public var isPlant: Bool { groupKind == "plants" }
}

/// A wrist-initiated mutation, sent phone-ward for the phone (source of
/// truth) to apply. The phone re-derives everything else (rescheduling the
/// notification, pushing a fresh snapshot back) — the watch never computes
/// due dates itself beyond display, even though it links `ReminderSchedule`
/// for that display math.
public enum WatchAction: Codable, Sendable, Equatable {
    case done(reminderId: UUID, date: Date)
    case setInterval(reminderId: UUID, days: Int)
    case snooze(reminderId: UUID)
}

public enum WatchSyncKeys {
    /// Key inside the `updateApplicationContext` dictionary; value is
    /// JSON-encoded `[ReminderSnapshot]` `Data`.
    public static let snapshotContextKey = "reminderSnapshots"
    /// Key inside the `transferUserInfo` dictionary; value is JSON-encoded
    /// `WatchAction` `Data`.
    public static let actionUserInfoKey = "watchAction"
    /// Prefix for thumbnail file transfers; the full transferred filename is
    /// "<prefix><reminderId>.jpg".
    public static let thumbnailFilePrefix = "plant-thumb-"
}
