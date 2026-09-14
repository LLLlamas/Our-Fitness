import Foundation
import SwiftData

@MainActor
enum LiveSessionCompletionService {
    enum Outcome { case saved, stale, failed }

    /// Both devices finish through this synchronous main-actor operation. There
    /// is no suspension between checking the active anchor, saving, and clearing.
    static func finish(_ ctx: ModelContext, profileId: UUID, startDate: Date,
                       elapsedSeconds: Int, bodyWeightLb: Double,
                       now: Date = Date(), save: (() throws -> Void)? = nil,
                       endPresentation: @MainActor () -> Void = endSystemPresentation) -> Outcome {
        guard let state = LiveSessionStore.active(for: profileId),
              abs(state.startDate.timeIntervalSince(startDate)) < 0.001 else { return .stale }
        let elapsed = min(max(0, elapsedSeconds), state.elapsedSeconds(now: now))
        guard Repos.completeLiveSession(ctx, state: state, elapsedSeconds: elapsed,
                                        bodyWeightLb: bodyWeightLb, save: save) else { return .failed }
        LiveSessionStore.clear()
        endPresentation()
        return .saved
    }
    private static func endSystemPresentation() {
        LiveSessionNotifier.cancel()
        if #available(iOS 16.2, *) { LiveSessionActivityController.end() }
    }
}
