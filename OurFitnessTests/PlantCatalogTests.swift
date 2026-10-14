import XCTest

// Pure Domain, no injectable clock needed here — PlantCatalog is static data
// plus deterministic pure functions (seededIntervalDays / suggestedAmountFlOz).
final class PlantCatalogTests: XCTestCase {

    // MARK: - Catalog invariants

    func test_catalog_has_unique_ids() {
        let ids = PlantCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "Plant species ids must be unique")
    }

    func test_catalog_baselineIntervalDays_within_range() {
        let range = PlantCatalog.minIntervalDays...PlantCatalog.maxIntervalDays
        for species in PlantCatalog.all {
            XCTAssertTrue(
                range.contains(species.baselineIntervalDays),
                "\(species.commonName) baselineIntervalDays \(species.baselineIntervalDays) out of \(range)"
            )
        }
    }

    func test_catalog_lowLightMultiplier_in_sane_range() {
        for species in PlantCatalog.all {
            XCTAssertGreaterThanOrEqual(species.lowLightMultiplier, 1.0, species.commonName)
            XCTAssertLessThanOrEqual(species.lowLightMultiplier, 2.5, species.commonName)
        }
    }

    func test_catalog_species_have_nonempty_descriptive_strings() {
        for species in PlantCatalog.all {
            XCTAssertFalse(species.soilCheck.isEmpty, "\(species.commonName) soilCheck")
            XCTAssertFalse(species.overwateringSigns.isEmpty, "\(species.commonName) overwateringSigns")
            XCTAssertFalse(species.underwateringSigns.isEmpty, "\(species.commonName) underwateringSigns")
            XCTAssertFalse(species.petToxicity.isEmpty, "\(species.commonName) petToxicity")
            XCTAssertFalse(species.botanicalName.isEmpty, "\(species.commonName) botanicalName")
            XCTAssertFalse(species.commonName.isEmpty, "commonName empty for id \(species.id)")
        }
    }

    // MARK: - species(id:) / entry(named:) lookups

    func test_species_id_round_trips_for_every_catalog_entry() {
        for species in PlantCatalog.all {
            XCTAssertEqual(PlantCatalog.species(id: species.id)?.id, species.id)
        }
    }

    func test_entry_named_commonName_round_trips_for_every_catalog_entry() {
        for species in PlantCatalog.all {
            XCTAssertEqual(
                PlantCatalog.entry(named: species.commonName)?.id, species.id,
                "lookup by \"\(species.commonName)\" should resolve back to itself"
            )
        }
    }

    func test_entry_named_pothos_resolves_by_name_and_alias() {
        XCTAssertEqual(PlantCatalog.entry(named: "pothos")?.id, "plant-pothos")
        XCTAssertEqual(PlantCatalog.entry(named: "devil's ivy")?.id, "plant-pothos")
    }

    func test_entry_named_snake_plant_resolves_by_name_and_alias() {
        XCTAssertEqual(PlantCatalog.entry(named: "snake plant")?.id, "plant-snake-plant")
        XCTAssertEqual(PlantCatalog.entry(named: "mother-in-law's tongue")?.id, "plant-snake-plant")
    }

    func test_entry_named_empty_string_returns_nil() {
        XCTAssertNil(PlantCatalog.entry(named: ""))
    }

    func test_entry_named_unknown_plant_returns_nil() {
        // Careful with the fixture here: entry(named:) has a shared-word
        // fallback (mirrors ExerciseInfo.catalogEntry(named:)), so a nonsense
        // query must avoid tokens/substrings that coincidentally overlap any
        // catalog commonName or alias (e.g. "...plant xyz" spuriously matches
        // "Jade plant" via the word "plant"; a "zz"-containing query matches
        // the "zz" alias for ZZ plant).
        XCTAssertNil(PlantCatalog.entry(named: "nonexistent houseplant foobar"))
    }

    func test_entry_named_is_case_insensitive() {
        XCTAssertEqual(PlantCatalog.entry(named: "POTHOS")?.id, "plant-pothos")
    }

    // MARK: - seededIntervalDays

    func test_seededIntervalDays_bright_returns_baseline() {
        for species in PlantCatalog.all {
            XCTAssertEqual(
                PlantCatalog.seededIntervalDays(for: species, light: .bright),
                species.baselineIntervalDays,
                species.commonName
            )
        }
    }

    func test_seededIntervalDays_low_gte_medium_gte_bright() {
        let species = PlantCatalog.species(id: "plant-pothos")!
        let bright = PlantCatalog.seededIntervalDays(for: species, light: .bright)
        let medium = PlantCatalog.seededIntervalDays(for: species, light: .medium)
        let low = PlantCatalog.seededIntervalDays(for: species, light: .low)
        XCTAssertGreaterThanOrEqual(medium, bright)
        XCTAssertGreaterThanOrEqual(low, medium)
    }

    func test_seededIntervalDays_clamps_extreme_species_to_max() {
        // baseline already at the ceiling, plus the richest plausible low-light
        // multiplier — the raw product would blow past maxIntervalDays.
        let extreme = PlantSpecies(
            id: "plant-test-extreme-max", commonName: "Test Extreme Max", botanicalName: "Testus extremus",
            aliases: [],
            baselineIntervalDays: PlantCatalog.maxIntervalDays, lowLightMultiplier: 2.5,
            soilCheck: "x", overwateringSigns: "x", underwateringSigns: "x", winterNote: "x",
            lowLightRating: .struggles, petToxicity: "x", waterClass: .light
        )
        XCTAssertEqual(
            PlantCatalog.seededIntervalDays(for: extreme, light: .low),
            PlantCatalog.maxIntervalDays
        )
    }

    func test_seededIntervalDays_clamps_extreme_species_to_min() {
        // baseline below the floor even before any light multiplier is applied.
        let extreme = PlantSpecies(
            id: "plant-test-extreme-min", commonName: "Test Extreme Min", botanicalName: "Testus minimus",
            aliases: [],
            baselineIntervalDays: 1, lowLightMultiplier: 1.0,
            soilCheck: "x", overwateringSigns: "x", underwateringSigns: "x", winterNote: "x",
            lowLightRating: .thrives, petToxicity: "x", waterClass: .light
        )
        XCTAssertEqual(
            PlantCatalog.seededIntervalDays(for: extreme, light: .bright),
            PlantCatalog.minIntervalDays
        )
    }

    // MARK: - suggestedAmountFlOz

    // PlantWaterClass is not CaseIterable, so the full case set is spelled out here.
    private let allWaterClasses: [PlantWaterClass] = [.light, .average, .moistureLover]

    func test_suggestedAmountFlOz_positive_for_every_combination() {
        for waterClass in allWaterClasses {
            for diameter in PlantCatalog.potDiameterOptions {
                let amount = PlantCatalog.suggestedAmountFlOz(waterClass: waterClass, potDiameterInches: diameter)
                XCTAssertGreaterThan(amount, 0, "\(waterClass) at \(diameter)in")
            }
        }
    }

    func test_suggestedAmountFlOz_increases_with_pot_diameter() {
        for waterClass in allWaterClasses {
            let amounts = PlantCatalog.potDiameterOptions.map {
                PlantCatalog.suggestedAmountFlOz(waterClass: waterClass, potDiameterInches: $0)
            }
            for i in 1..<amounts.count {
                XCTAssertGreaterThan(
                    amounts[i], amounts[i - 1],
                    "\(waterClass): \(PlantCatalog.potDiameterOptions[i - 1])in -> \(PlantCatalog.potDiameterOptions[i])in should increase"
                )
            }
        }
    }

    func test_suggestedAmountFlOz_light_less_than_moistureLover_for_same_pot_size() {
        for diameter in PlantCatalog.potDiameterOptions {
            let light = PlantCatalog.suggestedAmountFlOz(waterClass: .light, potDiameterInches: diameter)
            let moistureLover = PlantCatalog.suggestedAmountFlOz(waterClass: .moistureLover, potDiameterInches: diameter)
            XCTAssertLessThan(light, moistureLover, "at \(diameter)in")
        }
    }
}
