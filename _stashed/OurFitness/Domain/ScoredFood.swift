// Lifted out of live Domain/Models.swift during the post-Circuit audit:
// no live code consumes ScoredFood, only stashed Suggestions.swift does.
// Kept alongside the engine that uses it so a future revival is a single
// folder move.

import Foundation

public struct ScoredFood: Equatable, Sendable, Identifiable {
    public var food: FoodDTO
    public var score: Double
    public var reasons: [String]
    public var id: String { food.id }

    public init(food: FoodDTO, score: Double, reasons: [String]) {
        self.food = food
        self.score = score
        self.reasons = reasons
    }
}
