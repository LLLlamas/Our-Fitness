import XCTest

final class UnitsTests: XCTestCase {

    // Hostless target: Domain/Units.swift is compiled directly (no @testable
    // import). Conversions are pinned to known reference values; round-trips
    // must return to within floating tolerance.

    // MARK: - Weight (lb canonical)

    func test_weight_metric_value_and_format() {
        // 150 lb × 0.45359237 = 68.0388555 kg → "68.0"
        XCTAssertEqual(Units.weightValue(lb: 150, system: .metric), 68.0388555, accuracy: 0.0001)
        XCTAssertEqual(Units.formatWeight(lb: 150, system: .metric), "68.0")
        XCTAssertEqual(Units.formatWeightWithUnit(lb: 150, system: .metric), "68.0 kg")
    }

    func test_weight_imperial_passthrough() {
        XCTAssertEqual(Units.weightValue(lb: 150, system: .imperial), 150, accuracy: 0.0001)
        XCTAssertEqual(Units.formatWeightWithUnit(lb: 150, system: .imperial), "150.0 lb")
    }

    func test_weight_parse_roundtrip() {
        // User enters "70" kg → lb → back to kg display should read ~70.
        let lb = Units.parseWeightToLb("70", system: .metric)!
        XCTAssertEqual(lb, 70 * Units.lbPerKg, accuracy: 0.0001)
        XCTAssertEqual(Units.weightValue(lb: lb, system: .metric), 70, accuracy: 0.0001)
        // Imperial parse is a passthrough.
        XCTAssertEqual(Units.parseWeightToLb("185.5", system: .imperial)!, 185.5, accuracy: 0.0001)
    }

    func test_weight_parse_rejects_garbage() {
        XCTAssertNil(Units.parseWeightToLb("", system: .metric))
        XCTAssertNil(Units.parseWeightToLb("abc", system: .imperial))
    }

    // MARK: - Length / circumference (inches canonical)

    func test_length_metric_format_whole_cm() {
        // 34 in × 2.54 = 86.36 cm → "86"
        XCTAssertEqual(Units.formatLength(inches: 34, system: .metric), "86")
        XCTAssertEqual(Units.formatLengthWithUnit(inches: 34, system: .metric), "86 cm")
        XCTAssertEqual(Units.formatLengthWithUnit(inches: 34, system: .imperial), "34.0 in")
    }

    func test_length_parse_roundtrip() {
        // 86 cm → inches → back to cm ~86 (whole-cm rounding tolerance).
        let inches = Units.parseLengthToInches("86", system: .metric)!
        XCTAssertEqual(inches, 86 / Units.cmPerInch, accuracy: 0.0001)
        XCTAssertEqual(Units.formatLength(inches: inches, system: .metric), "86")
        XCTAssertEqual(Units.parseLengthToInches("32.5", system: .imperial)!, 32.5, accuracy: 0.0001)
    }

    // MARK: - Height (inches canonical; ft-in vs cm)

    func test_height_imperial_ft_in() {
        XCTAssertEqual(Units.formatHeight(inches: 67, system: .imperial), "5'7\"")
        XCTAssertEqual(Units.formatHeight(inches: 72, system: .imperial), "6'0\"")
    }

    func test_height_metric_cm() {
        // 67 in × 2.54 = 170.18 → 170 cm
        XCTAssertEqual(Units.formatHeight(inches: 67, system: .metric), "170 cm")
    }

    // MARK: - Volume (fl oz canonical)

    func test_volume_metric_rounds_to_nearest_10() {
        // 80 oz × 29.5735 = 2365.88 mL → nearest 10 = 2370
        XCTAssertEqual(Units.formatVolume(flOz: 80, system: .metric), "2370")
        XCTAssertEqual(Units.formatVolumeWithUnit(flOz: 80, system: .metric), "2370 mL")
        XCTAssertEqual(Units.formatVolumeWithUnit(flOz: 80, system: .imperial), "80 oz")
    }

    func test_volume_goal_step() {
        // Imperial keeps its 8 oz step; metric steps ~250 mL expressed in fl oz.
        XCTAssertEqual(Units.goalStepFlOz(8, system: .imperial), 8, accuracy: 0.0001)
        XCTAssertEqual(Units.goalStepFlOz(8, system: .metric), 250 / Units.mlPerFlOz, accuracy: 0.0001)
        // ~8.45 fl oz per 250 mL.
        XCTAssertEqual(Units.goalStepFlOz(8, system: .metric), 8.4535, accuracy: 0.001)
    }

    // MARK: - Distance (miles canonical)

    func test_distance_parse_roundtrip() {
        // 5 km → miles → back to km ~5.
        let miles = Units.parseDistanceToMiles("5", system: .metric)!
        XCTAssertEqual(miles, 5 / Units.kmPerMile, accuracy: 0.0001)
        XCTAssertEqual(miles * Units.kmPerMile, 5, accuracy: 0.0001)
        XCTAssertEqual(Units.parseDistanceToMiles("3.1", system: .imperial)!, 3.1, accuracy: 0.0001)
        XCTAssertNil(Units.parseDistanceToMiles("", system: .metric))
    }

    // MARK: - Unit labels

    func test_unit_labels() {
        XCTAssertEqual(Units.weightUnit(.metric), "kg")
        XCTAssertEqual(Units.weightUnit(.imperial), "lb")
        XCTAssertEqual(Units.lengthUnit(.metric), "cm")
        XCTAssertEqual(Units.volumeUnit(.metric), "mL")
        XCTAssertEqual(Units.distanceUnit(.metric), "km")
    }
}
