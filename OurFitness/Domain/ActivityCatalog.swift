// Catalog of duration-based activities for Live Sessions.
//
// Each activity carries a MET (intensity) used for the deterministic calorie
// estimate at session end: kcal = MET × bodyWeightKg × hours (CalorieEstimator).
// METs are from the Ainsworth 2011 Compendium of Physical Activities — the same
// source the rest of the app cites — picking representative general-effort codes.
//
// Pure Domain: no SwiftUI/SwiftData. SF Symbol names are stored as plain strings
// and rendered at the UI boundary.

import Foundation

public struct Activity: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let met: Double
    public let symbol: String       // SF Symbol name
    public let tracksDistance: Bool

    public init(id: String, name: String, met: Double, symbol: String, tracksDistance: Bool = false) {
        self.id = id
        self.name = name
        self.met = met
        self.symbol = symbol
        self.tracksDistance = tracksDistance
    }
}

public enum ActivityCatalog {

    /// Stable id used by the "Other" fallback entry. Its MET is a sensible
    /// moderate-effort default the user can adjust when starting a session.
    public static let otherId = "activity-other"
    public static let otherDefaultMET: Double = 5.0

    /// All offered activities. Ordered roughly most-common first. MET values are
    /// Ainsworth 2011 general-effort codes; see comments per entry.
    public static let all: [Activity] = [
        // Ball sports
        Activity(id: "activity-basketball-game",     name: "Basketball game",     met: 8.0,  symbol: "figure.basketball"),       // 15055 game
        Activity(id: "activity-basketball-shooting", name: "Basketball shooting", met: 4.5,  symbol: "figure.basketball"),       // 15075 shooting baskets
        Activity(id: "activity-soccer",              name: "Soccer",              met: 7.0,  symbol: "figure.soccer"),           // 15605 casual, general
        Activity(id: "activity-tennis",              name: "Tennis",              met: 7.3,  symbol: "figure.tennis"),           // 15675 general
        // Endurance / cardio
        Activity(id: "activity-running",             name: "Running",             met: 9.0,  symbol: "figure.run",          tracksDistance: true), // 12050 ~6 mph
        Activity(id: "activity-cycling",             name: "Cycling (moderate)",  met: 8.0,  symbol: "figure.outdoor.cycle", tracksDistance: true), // 01040 12–14 mph
        Activity(id: "activity-swimming",            name: "Swimming",            met: 7.0,  symbol: "figure.pool.swim"),        // 18310 leisurely, general
        Activity(id: "activity-rowing",              name: "Rowing machine",      met: 7.0,  symbol: "figure.rower"),            // 02050 vigorous, general
        Activity(id: "activity-jump-rope",           name: "Jump rope",           met: 11.8, symbol: "figure.jumprope"),         // 15551 general
        Activity(id: "activity-hiking",              name: "Hiking",              met: 6.0,  symbol: "figure.hiking",       tracksDistance: true), // 17080 cross-country
        Activity(id: "activity-walking",             name: "Walking",             met: 3.5,  symbol: "figure.walk",         tracksDistance: true), // 17190 ~3 mph
        // Skating
        Activity(id: "activity-ice-skating",         name: "Ice skating",         met: 7.0,  symbol: "figure.skating"),          // 19130 general
        Activity(id: "activity-inline-skating",      name: "Inline skating",      met: 7.5,  symbol: "figure.skating"),          // 19252 general
        // Studio / low-impact
        Activity(id: "activity-dancing",             name: "Dancing",             met: 5.5,  symbol: "figure.dance"),            // 03025 general
        Activity(id: "activity-pilates",             name: "Pilates",             met: 3.0,  symbol: "figure.pilates"),          // 06010 general
        Activity(id: "activity-yoga",                name: "Yoga",                met: 2.8,  symbol: "figure.yoga"),             // 02105 hatha
        // Catch-all
        Activity(id: otherId,                        name: "Other",               met: otherDefaultMET, symbol: "figure.mixed.cardio"),
    ]

    public static func activity(id: String) -> Activity? {
        all.first { $0.id == id }
    }

    /// Preset duration chips offered in the picker (minutes).
    public static let durationPresets: [Int] = [15, 30, 45, 60]
}
