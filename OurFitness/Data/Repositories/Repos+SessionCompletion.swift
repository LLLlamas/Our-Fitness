import Foundation
import SwiftData

extension Repos {
    /// The timestamp anchor and profile identify a live session across existing
    /// phone/watch payloads. Check durable history as well as active state so a
    /// crash after saving but before clearing the anchor cannot duplicate a log.
    static func completeLiveSession(_ ctx: ModelContext, state: LiveSessionState,
                                    elapsedSeconds: Int, bodyWeightLb: Double,
                                    dizziness: DizzinessReport? = nil,
                                    save: (() throws -> Void)? = nil) -> Bool {
        RepositoryWrite.perform(ctx, save: save) {
            let profileId = state.profileId
            let start = state.startDate
            let minutes = max(1, Int((Double(elapsedSeconds) / 60).rounded()))
            if state.activityId == ActivityCatalog.pilatesId {
                let descriptor = FetchDescriptor<PilatesSessionModel>(predicate: #Predicate {
                    $0.profileId == profileId && $0.date == start
                })
                guard try ctx.fetchCount(descriptor) == 0 else { return }
                ctx.insert(PilatesSessionModel(snapshot: PilatesSessionDTO(
                    profileId: profileId, date: start, durationMinutes: minutes, focusAreas: [],
                    dizziness: dizziness)))
            } else {
                let activityId = state.activityId
                let descriptor = FetchDescriptor<ActivitySessionModel>(predicate: #Predicate {
                    $0.profileId == profileId && $0.date == start && $0.activityId == activityId
                })
                guard try ctx.fetchCount(descriptor) == 0 else { return }
                ctx.insert(ActivitySessionModel(snapshot: ActivitySessionDTO(
                    profileId: profileId, date: start, activityId: activityId,
                    activityName: state.activityName, met: state.met,
                    durationMinutes: minutes, expectedMinutes: state.expectedMinutes,
                    caloriesEst: CalorieEstimator.caloriesForActivity(
                        met: state.met, minutes: Double(elapsedSeconds) / 60, bodyWeightLb: bodyWeightLb),
                    dizziness: dizziness)))
            }
        }
    }

    /// Stores Health's average/peak heart rate on a flagged live session, found
    /// by the same (profile, start, activity) identity `completeLiveSession` uses.
    /// False with nothing written when the session is gone or wasn't flagged —
    /// heart rate is never attached to an unflagged session.
    static func recordDizzyHeartRate(_ ctx: ModelContext, state: LiveSessionState,
                                     averageBpm: Double, peakBpm: Double,
                                     save: (() throws -> Void)? = nil) -> Bool {
        RepositoryWrite.perform(ctx, save: save) {
            let profileId = state.profileId
            let start = state.startDate
            if state.activityId == ActivityCatalog.pilatesId {
                let descriptor = FetchDescriptor<PilatesSessionModel>(predicate: #Predicate {
                    $0.profileId == profileId && $0.date == start
                })
                guard let model = try ctx.fetch(descriptor).first,
                      var report = model.dizziness else { throw RepositoryWriteError.missingRecord }
                report.averageHeartRateBpm = averageBpm
                report.peakHeartRateBpm = peakBpm
                model.dizziness = report
            } else {
                let activityId = state.activityId
                let descriptor = FetchDescriptor<ActivitySessionModel>(predicate: #Predicate {
                    $0.profileId == profileId && $0.date == start && $0.activityId == activityId
                })
                guard let model = try ctx.fetch(descriptor).first,
                      var report = model.dizziness else { throw RepositoryWriteError.missingRecord }
                report.averageHeartRateBpm = averageBpm
                report.peakHeartRateBpm = peakBpm
                model.dizziness = report
            }
        }
    }
}
