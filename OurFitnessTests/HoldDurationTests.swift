import XCTest

final class HoldDurationTests: XCTestCase {

    // Hostless target: Domain/HoldDuration.swift is compiled directly.

    func test_parse_plainSeconds() {
        XCTAssertEqual(HoldDuration.parseSeconds("47"), 47)
        XCTAssertEqual(HoldDuration.parseSeconds("  47  "), 47)
        XCTAssertEqual(HoldDuration.parseSeconds("0"), 0)
        XCTAssertEqual(HoldDuration.parseSeconds("90"), 90)
        XCTAssertEqual(HoldDuration.parseSeconds("3600"), 3600)
    }

    func test_parse_trailingS() {
        XCTAssertEqual(HoldDuration.parseSeconds("47s"), 47)
        XCTAssertEqual(HoldDuration.parseSeconds("47 s"), 47)
        XCTAssertEqual(HoldDuration.parseSeconds("1:30s"), 90)
    }

    func test_parse_minutesColonSeconds() {
        XCTAssertEqual(HoldDuration.parseSeconds("1:30"), 90)
        XCTAssertEqual(HoldDuration.parseSeconds("0:45"), 45)
        XCTAssertEqual(HoldDuration.parseSeconds("2:00"), 120)
        XCTAssertEqual(HoldDuration.parseSeconds("1:59"), 119)
        XCTAssertEqual(HoldDuration.parseSeconds("60:00"), 3600)
    }

    func test_parse_rejects() {
        for bad in ["", "   ", "s", "-5", "-1:30", ":30", "1:", "1:75", "1:5", "1:60",
                    "1.5", "45.5", "1:30:00", "abc", "4 7", "1::30", "+5", "٤٧"] {
            XCTAssertNil(HoldDuration.parseSeconds(bad), "should reject \"\(bad)\"")
        }
    }

    func test_parse_hugeNumbersDoNotCrash() {
        XCTAssertNil(HoldDuration.parseSeconds("99999999999999999999999"))
        XCTAssertNil(HoldDuration.parseSeconds("99999999999999999999:30"))
    }

    func test_entryText() {
        XCTAssertEqual(HoldDuration.entryText(47), "47")
        XCTAssertEqual(HoldDuration.entryText(59), "59")
        XCTAssertEqual(HoldDuration.entryText(60), "1:00")
        XCTAssertEqual(HoldDuration.entryText(90), "1:30")
        XCTAssertEqual(HoldDuration.entryText(3600), "60:00")
    }

    func test_roundTrip_isIdentity() {
        // An untouched Edit Set must not re-price a logged hold.
        for seconds in [47, 90, 3600] {
            XCTAssertEqual(HoldDuration.parseSeconds(HoldDuration.entryText(seconds)), seconds)
        }
        for seconds in 0...3600 {
            XCTAssertEqual(HoldDuration.parseSeconds(HoldDuration.entryText(seconds)), seconds)
        }
    }

    func test_maxSeconds() {
        XCTAssertEqual(HoldDuration.maxSeconds, 3600)
    }
}
