import XCTest

// Pure Domain coverage for the water preset model: built-in sizes, custom-preset
// ordering, and the DTO→CupPreset adapter.
final class WaterPresetTests: XCTestCase {

    func testBuiltInSizes() {
        let oz = Water.presets.map(\.flOz)
        XCTAssertEqual(oz, [8, 12, 16, 32])
        XCTAssertFalse(Water.presets.contains { $0.isCustom })
        XCTAssertEqual(Water.presets.last?.icon, .bottle)
    }

    func testCustomPresetsAppendAfterBuiltInsInOrder() {
        let uid = UUID()
        let now = Date(timeIntervalSince1970: 1_780_488_000)
        let a = WaterCupPresetDTO(userId: uid, name: "B-second", flOz: 24, icon: .glassLarge,
                                  sortOrder: 1, createdAt: now)
        let b = WaterCupPresetDTO(userId: uid, name: "A-first", flOz: 20, icon: .glassMedium,
                                  sortOrder: 0, createdAt: now.addingTimeInterval(10))
        let all = Water.allPresets(custom: [a, b])

        XCTAssertEqual(all.count, Water.presets.count + 2)
        // Built-ins first, then customs sorted by sortOrder.
        XCTAssertEqual(Array(all.prefix(4)).map(\.flOz), [8, 12, 16, 32])
        XCTAssertEqual(all[4].label, "A-first")   // sortOrder 0
        XCTAssertEqual(all[5].label, "B-second")  // sortOrder 1
        XCTAssertTrue(all[4].isCustom)
    }

    func testDTOAdapterMarksCustom() {
        let p = WaterCupPresetDTO(userId: UUID(), name: "My tumbler", flOz: 26, icon: .glassLarge)
        let preset = p.asPreset
        XCTAssertTrue(preset.isCustom)
        XCTAssertEqual(preset.label, "My tumbler")
        XCTAssertEqual(preset.flOz, 26)
        XCTAssertEqual(preset.id, p.id.uuidString)
    }

    func testIconRawRoundTrips() {
        for icon in Water.CupIcon.allCases {
            XCTAssertEqual(Water.CupIcon(rawValue: icon.rawValue), icon)
        }
    }
}
