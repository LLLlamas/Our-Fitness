// Plain-English copy explaining why each Reset cap exists.
// Pure data — no SwiftUI, no SwiftData. Revise here without touching views.
//
// Sources cited inline so a curious user can verify; not medical advice.

import Foundation

public enum CapKind: String, Codable, Sendable {
    case sodium, addedSugar, saturatedFat, fiber
}

public struct CapExplanation: Equatable, Sendable, Identifiable {
    public let kind: CapKind
    public let title: String
    public let limit: String
    public let whyItMatters: String
    public let source: String

    public var id: String { kind.rawValue }
}

public enum CapExplanations {

    public static let sodium = CapExplanation(
        kind: .sodium,
        title: "Sodium",
        limit: "≤ 1,500 mg/day",
        whyItMatters: """
        The American Heart Association's recommended cap for adults with elevated BP \
        or a family history of heart disease. Most Americans hit this in a single \
        restaurant meal. Lowering sodium directly lowers systolic BP by 5–6 mmHg \
        on average — meaningful for the cholesterol/heart-risk profile.
        """,
        source: "American Heart Association"
    )

    public static let addedSugar = CapExplanation(
        kind: .addedSugar,
        title: "Added Sugar",
        limit: "≤ 25 g/day",
        whyItMatters: """
        The AHA caps added sugar at 25 g/day for women and 36 g/day for men; we use \
        the tighter 25 g for Reset. Added sugar (not the natural sugar in fruit) \
        raises triglycerides, drives insulin spikes, and crowds out fiber and \
        protein. One regular soda already exceeds the daily cap.
        """,
        source: "American Heart Association"
    )

    public static let saturatedFat = CapExplanation(
        kind: .saturatedFat,
        title: "Saturated Fat",
        limit: "< 10% of calories (~22 g on a 2,000-cal day)",
        whyItMatters: """
        The AHA recommends keeping saturated fat under 10% of total calories — \
        roughly 22 g/day at 2,000 calories. Saturated fat raises LDL ("bad") \
        cholesterol more reliably than dietary cholesterol does. Swapping it for \
        unsaturated fat (olive oil, nuts, fatty fish) is one of the clearest \
        dietary levers on LDL.
        """,
        source: "American Heart Association"
    )

    public static let fiber = CapExplanation(
        kind: .fiber,
        title: "Fiber Floor",
        limit: "≥ 35 g/day",
        whyItMatters: """
        USDA dietary guidelines target 25–38 g/day; Reset uses 35 g as a floor. \
        Soluble fiber binds bile acids in the gut, forcing the liver to pull \
        cholesterol from the blood to make more — a direct LDL-lowering mechanism. \
        Fiber also improves satiety and blunts blood-sugar spikes.
        """,
        source: "USDA Dietary Guidelines"
    )

    public static let all: [CapExplanation] = [sodium, addedSugar, saturatedFat, fiber]

    public static func explanation(for kind: CapKind) -> CapExplanation {
        switch kind {
        case .sodium:       return sodium
        case .addedSugar:   return addedSugar
        case .saturatedFat: return saturatedFat
        case .fiber:        return fiber
        }
    }
}
