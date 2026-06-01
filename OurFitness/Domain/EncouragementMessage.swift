// Encouragement system — message value type (Phase 1).
//
// A single, render-ready unit of positive feedback. The view layer turns a
// message into a toast or an inline strip; the science line surfaces in a sheet.
//
// Rule: never import SwiftData or SwiftUI from this file. Pure Swift only.

import Foundation

public enum EncouragementTone: Sendable {
    case celebrate     // milestone hit — the warm "you did it" beat
    case impressed     // above-and-beyond; research sweet spot or elite range
    case approaching   // close to a goal; a gentle pull over the line
    case nudge         // light prompt to keep moving
    case scienceTip    // the why-it-matters fact, framed as a reward
    case projection    // forward-looking numeric estimate
}

public struct EncouragementMessage: Sendable {
    public let headline: String        // ≤50 chars, shown bold
    public let detail: String          // 1–2 sentences
    public let scienceLine: String?    // citation fact, shown in a sheet
    public let tone: EncouragementTone
    public let sfSymbol: String

    public init(
        headline: String,
        detail: String,
        scienceLine: String? = nil,
        tone: EncouragementTone,
        sfSymbol: String
    ) {
        self.headline = headline
        self.detail = detail
        self.scienceLine = scienceLine
        self.tone = tone
        self.sfSymbol = sfSymbol
    }
}
