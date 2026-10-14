import Foundation

enum SessionInputValidation {
    /// Preserve offline actions while rejecting invalid or far-future anchors.
    static func validDate(_ date: Date, now: Date) -> Bool {
        let seconds = date.timeIntervalSinceReferenceDate
        return seconds.isFinite && seconds >= 0 && date <= now.addingTimeInterval(300)
    }

    static func start(activityId: String, suppliedMET: Double, expectedMinutes: Int,
                      startDate: Date, profileId: UUID, now: Date) -> LiveSessionState? {
        guard let activity = ActivityCatalog.activity(id: activityId),
              validDate(startDate, now: now), (5...240).contains(expectedMinutes) else { return nil }
        // Other intentionally supports user-selected intensity on the phone.
        // Known activities always use the catalog, irrespective of wire values.
        let met = activity.id == ActivityCatalog.otherId ? suppliedMET : activity.met
        guard met.isFinite, (2...12).contains(met) else { return nil }
        return LiveSessionState(startDate: startDate, activityId: activity.id,
                                activityName: activity.name, met: met,
                                expectedMinutes: expectedMinutes, profileId: profileId)
    }
}
