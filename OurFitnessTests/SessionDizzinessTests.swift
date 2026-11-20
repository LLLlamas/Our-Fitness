import XCTest

// Pure Domain: the "Felt dizzy" flag (cardio plan §10 Q2). Severity → Health
// severity mapping, which sessions get a heart-rate read and a Health write,
// the both-or-neither heart-rate rule, the neutral history line, and old
// payloads without the field. Dates are pinned; no bare `Date()`.
final class SessionDizzinessTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: Severity mapping

    func testNoSeverityMapsToUnspecified() {
        XCTAssertEqual(SessionDizziness.healthSeverity(nil), .unspecified)
    }

    func testEachSeverityMapsToItsHealthCase() {
        XCTAssertEqual(SessionDizziness.healthSeverity(.mild), .mild)
        XCTAssertEqual(SessionDizziness.healthSeverity(.moderate), .moderate)
        XCTAssertEqual(SessionDizziness.healthSeverity(.severe), .severe)
    }

    func testSeverityRawValuesArePinned() {
        // Persisted in `dizzySeverityRaw`; renaming one needs a schema bump.
        XCTAssertEqual(DizzinessSeverity.allCases.map(\.rawValue), ["mild", "moderate", "severe"])
    }

    // MARK: Which sessions get heart rate + a Health write

    func testFlaggedLiveSessionUsesItsRealWindow() {
        let end = start.addingTimeInterval(1_800)
        let window = SessionDizziness.healthWindow(flagged: true, origin: .live(start: start, end: end))
        XCTAssertEqual(window, DateInterval(start: start, end: end))
    }

    func testSessionLoggedAfterTheFactNeverQueriesOrWrites() {
        XCTAssertNil(SessionDizziness.healthWindow(flagged: true, origin: .loggedAfter))
    }

    func testUnflaggedSessionNeverQueriesOrWrites() {
        XCTAssertNil(SessionDizziness.healthWindow(
            flagged: false, origin: .live(start: start, end: start.addingTimeInterval(600))))
        XCTAssertNil(SessionDizziness.healthWindow(flagged: false, origin: .loggedAfter))
    }

    func testLiveWindowWithNoLengthIsSkipped() {
        XCTAssertNil(SessionDizziness.healthWindow(flagged: true, origin: .live(start: start, end: start)))
        XCTAssertNil(SessionDizziness.healthWindow(
            flagged: true, origin: .live(start: start, end: start.addingTimeInterval(-60))))
    }

    // MARK: Heart rate: real samples or nothing

    func testHeartRateNeedsBothValues() {
        XCTAssertNil(SessionDizziness.heartRate(average: nil, peak: nil))
        XCTAssertNil(SessionDizziness.heartRate(average: 120, peak: nil))
        XCTAssertNil(SessionDizziness.heartRate(average: nil, peak: 150))
        XCTAssertNil(SessionDizziness.heartRate(average: 0, peak: 0))
        XCTAssertNil(SessionDizziness.heartRate(average: .nan, peak: 150))
        let hr = SessionDizziness.heartRate(average: 121.6, peak: 150)
        XCTAssertEqual(hr?.average, 121.6)
        XCTAssertEqual(hr?.peak, 150)
    }

    // MARK: History line

    func testSummaryWithSeverityAndHeartRate() {
        let report = DizzinessReport(severity: .moderate, averageHeartRateBpm: 127.6, peakHeartRateBpm: 151.2)
        XCTAssertEqual(SessionDizziness.summary(report),
                       "Felt dizzy · Moderate · Heart rate: average 128, peak 151")
    }

    func testSummaryWithoutHeartRateSaysSoAndNeverEstimates() {
        XCTAssertEqual(SessionDizziness.summary(DizzinessReport()), "Felt dizzy · No heart-rate data")
        XCTAssertEqual(SessionDizziness.summary(DizzinessReport(severity: .mild, averageHeartRateBpm: 110)),
                       "Felt dizzy · Mild · No heart-rate data")
    }

    func testSummaryHasNoWarningOrAdviceWords() {
        for severity in [nil] + DizzinessSeverity.allCases.map(Optional.some) {
            let text = SessionDizziness.summary(DizzinessReport(severity: severity)).lowercased()
            for word in ["doctor", "warning", "danger", "stop", "should", "risk", "!"] {
                XCTAssertFalse(text.contains(word), "\(word) in \(text)")
            }
        }
    }

    // MARK: DTO compatibility

    func testActivitySessionWithoutDizzinessKeyDecodesAsNotFlagged() throws {
        let original = ActivitySessionDTO(profileId: UUID(), date: start, activityId: "activity-walking",
                                          activityName: "Walking", met: 3.5, durationMinutes: 30,
                                          expectedMinutes: 30)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json.removeValue(forKey: "dizziness")
        let decoded = try JSONDecoder().decode(ActivitySessionDTO.self,
                                               from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.dizziness)
        XCTAssertEqual(decoded, original)
    }

    func testFlaggedSessionsRoundTripThroughCodable() throws {
        let report = DizzinessReport(severity: .severe, averageHeartRateBpm: 132, peakHeartRateBpm: 160)
        let activity = ActivitySessionDTO(profileId: UUID(), date: start, activityId: "activity-walking",
                                          activityName: "Walking", met: 3.5, durationMinutes: 30,
                                          expectedMinutes: 30, dizziness: report)
        let pilates = PilatesSessionDTO(profileId: UUID(), date: start, durationMinutes: 40,
                                        focusAreas: [.core], dizziness: DizzinessReport())
        XCTAssertEqual(try JSONDecoder().decode(ActivitySessionDTO.self, from: JSONEncoder().encode(activity)), activity)
        XCTAssertEqual(try JSONDecoder().decode(PilatesSessionDTO.self, from: JSONEncoder().encode(pilates)), pilates)
    }
}
