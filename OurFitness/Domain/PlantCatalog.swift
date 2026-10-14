// Curated houseplant watering catalog.
//
// Baseline intervals assume a 6" plastic pot, well-draining mix, bright-indirect
// light, 65-75F, and the active growing season. seededIntervalDays adjusts for
// the room's actual light level. Winter guidance ships as copy only
// (winterNote) — NOT a math multiplier, so a user's edited interval always
// means what it says instead of silently drifting with the season.
//
// Sourced from university extension services and botanical gardens (MU
// Extension G6510, Clemson HGIC, UMD Extension, UMN Extension, Iowa State,
// Missouri Botanical Garden, NYBG, NC State Plant Toolbox, WSU King County,
// American Orchid Society) plus ASPCA's toxic/non-toxic plant list for
// toxicity. Secondary sources (The Sill, Costa Farms, Joy Us Garden) filled in
// interval numbers and the pot-volume amount fraction where extension sources
// didn't give one. Where sources conflicted, the consensus midpoint is used.
//
// Pure Domain: no SwiftUI/SwiftData. SF Symbol names are stored as plain
// strings and rendered at the UI boundary.

import Foundation

public enum PlantLightLevel: String, Codable, CaseIterable, Sendable {
    case bright, medium, low

    public var label: String {
        switch self {
        case .bright: return "Bright indirect"
        case .medium: return "Medium light"
        case .low:    return "Low light"
        }
    }
}

public enum PlantWaterClass: String, Codable, Sendable {
    case light          // drought-tolerant: succulents, cacti, snake plant, ZZ, jade, aloe
    case average         // most tropical foliage
    case moistureLover    // ferns, peace lily, calathea, croton, bird of paradise
}

public enum LowLightRating: String, Codable, Sendable {
    case thrives, tolerates, struggles
}

public struct PlantSpecies: Identifiable, Equatable, Sendable {
    public let id: String
    public let commonName: String
    public let botanicalName: String
    public let aliases: [String]
    /// Midpoint of the researched range, in days, at bright-indirect light.
    public let baselineIntervalDays: Int
    /// Multiplier applied to the baseline when the room is low light.
    public let lowLightMultiplier: Double
    public let soilCheck: String
    public let overwateringSigns: String
    public let underwateringSigns: String
    public let winterNote: String
    public let lowLightRating: LowLightRating
    public let petToxicity: String
    public let waterClass: PlantWaterClass
    public let sfSymbol: String

    public init(id: String, commonName: String, botanicalName: String, aliases: [String],
                baselineIntervalDays: Int, lowLightMultiplier: Double, soilCheck: String,
                overwateringSigns: String, underwateringSigns: String, winterNote: String,
                lowLightRating: LowLightRating, petToxicity: String, waterClass: PlantWaterClass,
                sfSymbol: String = "leaf.fill") {
        self.id = id
        self.commonName = commonName
        self.botanicalName = botanicalName
        self.aliases = aliases
        self.baselineIntervalDays = baselineIntervalDays
        self.lowLightMultiplier = lowLightMultiplier
        self.soilCheck = soilCheck
        self.overwateringSigns = overwateringSigns
        self.underwateringSigns = underwateringSigns
        self.winterNote = winterNote
        self.lowLightRating = lowLightRating
        self.petToxicity = petToxicity
        self.waterClass = waterClass
        self.sfSymbol = sfSymbol
    }
}

public enum PlantCatalog {

    public static let minIntervalDays = 2
    public static let maxIntervalDays = 60
    public static let potDiameterOptions = [4, 6, 8, 10]
    public static let drainageCopy = "or until water runs from the drainage hole; then empty the saucer"

    /// Stable id for a plant added without picking a species from the catalog.
    public static let customId = "plant-custom"

    // Alphabetical by common name.
    public static let all: [PlantSpecies] = [
        PlantSpecies(
            id: "plant-aloe-vera", commonName: "Aloe vera", botanicalName: "Aloe vera",
            aliases: ["aloe"],
            baselineIntervalDays: 17, lowLightMultiplier: 2.0,
            soilCheck: "Water when the soil is fully dry, then soak deeply.",
            overwateringSigns: "Mushy, translucent leaves.",
            underwateringSigns: "Thin, curled, puckered leaves.",
            winterNote: "Water even less in winter dormancy — roughly every 4-6 weeks.",
            lowLightRating: .struggles, petToxicity: "Toxic to cats and dogs (aloin; GI upset).",
            waterClass: .light
        ),
        PlantSpecies(
            id: "plant-anthurium", commonName: "Anthurium", botanicalName: "Anthurium andraeanum",
            aliases: ["flamingo flower"],
            baselineIntervalDays: 8, lowLightMultiplier: 1.5,
            soilCheck: "Water when the top 1-2 inches of soil are dry.",
            overwateringSigns: "Yellow leaves, root rot — very sensitive to soggy soil.",
            underwateringSigns: "Drooping leaves, brown tips.",
            winterNote: "Stretch to every 10-14+ days in winter.",
            lowLightRating: .tolerates, petToxicity: "Toxic to cats and dogs (oxalates; oral irritation).",
            waterClass: .average
        ),
        PlantSpecies(
            id: "plant-areca-palm", commonName: "Areca palm", botanicalName: "Dypsis lutescens",
            aliases: ["butterfly palm", "golden cane palm"],
            baselineIntervalDays: 8, lowLightMultiplier: 1.5,
            soilCheck: "Water when the top 1 inch of soil is dry.",
            overwateringSigns: "Yellow fronds, root rot, brown tips.",
            underwateringSigns: "Brown, crispy tips and fronds.",
            winterNote: "Stretch to every 2-3 weeks in winter.",
            lowLightRating: .struggles, petToxicity: "Non-toxic to cats and dogs.",
            waterClass: .average
        ),
        PlantSpecies(
            id: "plant-bird-of-paradise", commonName: "Bird of paradise", botanicalName: "Strelitzia reginae",
            aliases: ["strelitzia"],
            baselineIntervalDays: 10, lowLightMultiplier: 1.5,
            soilCheck: "Water when the top 1-2 inches of soil are dry.",
            overwateringSigns: "Yellow lower leaves, mushy base.",
            underwateringSigns: "Crispy, curled leaf edges.",
            winterNote: "Stretch to every 2-3 weeks in winter.",
            lowLightRating: .struggles, petToxicity: "Mildly toxic to cats and dogs (GI upset).",
            waterClass: .moistureLover
        ),
        PlantSpecies(
            id: "plant-boston-fern", commonName: "Boston fern", botanicalName: "Nephrolepis exaltata",
            aliases: ["fern"],
            baselineIntervalDays: 3, lowLightMultiplier: 1.4,
            soilCheck: "Water as soon as the surface feels just dry — never let it fully dry out.",
            overwateringSigns: "Yellow, limp fronds sitting in soggy soil.",
            underwateringSigns: "Gray-green fronds, mass leaflet shedding.",
            winterNote: "Cuts back to about weekly with a cool winter rest.",
            lowLightRating: .tolerates, petToxicity: "Non-toxic to cats and dogs.",
            waterClass: .moistureLover
        ),
        PlantSpecies(
            id: "plant-cactus", commonName: "Cactus", botanicalName: "Cactaceae spp. (desert types)",
            aliases: ["desert cactus"],
            baselineIntervalDays: 22, lowLightMultiplier: 2.0,
            soilCheck: "Water only when the soil is fully, deeply dry.",
            overwateringSigns: "Soft, blackening base — rot.",
            underwateringSigns: "Shriveling, puckering.",
            winterNote: "Water every 4-6 weeks in winter, or withhold almost entirely.",
            lowLightRating: .struggles, petToxicity: "Non-toxic to cats and dogs (spines are a mechanical hazard).",
            waterClass: .light
        ),
        PlantSpecies(
            id: "plant-calathea", commonName: "Calathea", botanicalName: "Goeppertia spp. / Maranta spp.",
            aliases: ["prayer plant"],
            baselineIntervalDays: 5, lowLightMultiplier: 1.4,
            soilCheck: "Keep evenly moist; only let the top 1/2-1 inch dry between waterings.",
            overwateringSigns: "Yellowing, limp mushy stems, rot.",
            underwateringSigns: "Curled leaves, crispy brown edges.",
            winterNote: "Stretch to every 7-10 days in winter.",
            lowLightRating: .tolerates, petToxicity: "Non-toxic to cats and dogs.",
            waterClass: .moistureLover
        ),
        PlantSpecies(
            id: "plant-chinese-evergreen", commonName: "Chinese evergreen", botanicalName: "Aglaonema spp.",
            aliases: ["aglaonema"],
            baselineIntervalDays: 8, lowLightMultiplier: 1.75,
            soilCheck: "Water when the top 1-2 inches of soil are dry.",
            overwateringSigns: "Yellow leaves, mushy stalks.",
            underwateringSigns: "Curling, dry tips.",
            winterNote: "Stretch to every 2-3 weeks in winter.",
            lowLightRating: .thrives, petToxicity: "Toxic to cats and dogs (oxalates; oral irritation).",
            waterClass: .average
        ),
        PlantSpecies(
            id: "plant-croton", commonName: "Croton", botanicalName: "Codiaeum variegatum",
            aliases: [],
            baselineIntervalDays: 6, lowLightMultiplier: 1.5,
            soilCheck: "Water when the top 1 inch of soil is dry.",
            overwateringSigns: "Wilting despite wet soil, yellow leaf drop.",
            underwateringSigns: "Dramatic drooping and leaf drop.",
            winterNote: "Stretch to every 10-14 days in winter.",
            lowLightRating: .struggles, petToxicity: "Toxic to cats and dogs (sap irritant; GI upset).",
            waterClass: .moistureLover
        ),
        PlantSpecies(
            id: "plant-dieffenbachia", commonName: "Dieffenbachia", botanicalName: "Dieffenbachia seguine",
            aliases: ["dumb cane"],
            baselineIntervalDays: 8, lowLightMultiplier: 1.5,
            soilCheck: "Water when the top 1 inch of soil is dry.",
            overwateringSigns: "Yellow lower leaves; droops even while soil is wet.",
            underwateringSigns: "Wilting, brown crispy edges.",
            winterNote: "Stretch to every 2-3 weeks in winter.",
            lowLightRating: .tolerates, petToxicity: "Toxic to cats and dogs — notorious for oral swelling/pain.",
            waterClass: .average
        ),
        PlantSpecies(
            id: "plant-dracaena-marginata", commonName: "Dracaena marginata", botanicalName: "Dracaena marginata",
            aliases: ["dragon tree"],
            baselineIntervalDays: 12, lowLightMultiplier: 1.5,
            soilCheck: "Water when the top 1 inch of soil is dry. Use filtered water — sensitive to fluoride.",
            overwateringSigns: "Soft stem, yellow drooping leaves.",
            underwateringSigns: "Brown, crispy tips, leaf drop.",
            winterNote: "Stretch to every 3-4 weeks in winter.",
            lowLightRating: .tolerates, petToxicity: "Toxic to cats and dogs, especially cats (saponins).",
            waterClass: .average
        ),
        PlantSpecies(
            id: "plant-english-ivy", commonName: "English ivy", botanicalName: "Hedera helix",
            aliases: ["ivy"],
            baselineIntervalDays: 7, lowLightMultiplier: 1.5,
            soilCheck: "Water when the top 1 inch of soil is dry; keep slightly moist, never soggy.",
            overwateringSigns: "Yellow leaves, rot.",
            underwateringSigns: "Dry, crispy leaves; watch for spider mites.",
            winterNote: "Stretch to every 10-14 days; likes it cool in winter.",
            lowLightRating: .tolerates, petToxicity: "Toxic to cats and dogs (saponins).",
            waterClass: .average
        ),
        PlantSpecies(
            id: "plant-fiddle-leaf-fig", commonName: "Fiddle-leaf fig", botanicalName: "Ficus lyrata",
            aliases: ["fig", "fig plant", "fiddle leaf fig"],
            baselineIntervalDays: 8, lowLightMultiplier: 1.5,
            soilCheck: "Water when the top 1-2 inches of soil are dry.",
            overwateringSigns: "Dark brown blotches starting mid-leaf, leaf drop.",
            underwateringSigns: "Tan, crispy edges, curling, leaf drop.",
            winterNote: "Stretch to roughly 1.5x the interval in winter.",
            lowLightRating: .struggles, petToxicity: "Toxic to cats and dogs (sap; GI upset).",
            waterClass: .average
        ),
        PlantSpecies(
            id: "plant-heartleaf-philodendron", commonName: "Heartleaf philodendron", botanicalName: "Philodendron hederaceum",
            aliases: ["philodendron"],
            baselineIntervalDays: 10, lowLightMultiplier: 1.5,
            soilCheck: "Water when the top 1 inch of soil is dry.",
            overwateringSigns: "Yellow leaves, mushy stems.",
            underwateringSigns: "Drooping, brown crispy tips.",
            winterNote: "Stretch to roughly 1.5x the interval in winter.",
            lowLightRating: .tolerates, petToxicity: "Toxic to cats and dogs (oxalates; oral irritation).",
            waterClass: .average
        ),
        PlantSpecies(
            id: "plant-jade", commonName: "Jade plant", botanicalName: "Crassula ovata",
            aliases: ["jade"],
            baselineIntervalDays: 17, lowLightMultiplier: 2.0,
            soilCheck: "Water when the soil is mostly to fully dry.",
            overwateringSigns: "Leaf drop, soft squishy yellow leaves.",
            underwateringSigns: "Shriveled, wrinkled leaves.",
            winterNote: "Water monthly or less in winter dormancy.",
            lowLightRating: .struggles, petToxicity: "Toxic to cats and dogs (vomiting, lethargy).",
            waterClass: .light
        ),
        PlantSpecies(
            id: "plant-money-tree", commonName: "Money tree", botanicalName: "Pachira aquatica",
            aliases: ["pachira"],
            baselineIntervalDays: 10, lowLightMultiplier: 1.75,
            soilCheck: "Water when the top 1-2 inches of soil are dry. Never let it sit in standing water.",
            overwateringSigns: "Yellow leaves, soft trunk — root/trunk rot is its #1 killer.",
            underwateringSigns: "Crispy leaves, leaf drop.",
            winterNote: "Stretch to every 3-5 weeks in winter.",
            lowLightRating: .tolerates, petToxicity: "Non-toxic to cats and dogs.",
            waterClass: .average
        ),
        PlantSpecies(
            id: "plant-monstera", commonName: "Monstera deliciosa", botanicalName: "Monstera deliciosa",
            aliases: ["monstera", "swiss cheese plant"],
            baselineIntervalDays: 10, lowLightMultiplier: 1.5,
            soilCheck: "Water when the top 1-2 inches of soil are dry.",
            overwateringSigns: "Yellow lower leaves, black spots on the stem.",
            underwateringSigns: "Drooping, curling, crisp edges.",
            winterNote: "Growth slows and it needs water less often in winter.",
            lowLightRating: .tolerates, petToxicity: "Toxic to cats and dogs (oxalates; oral irritation).",
            waterClass: .average
        ),
        PlantSpecies(
            id: "plant-parlor-palm", commonName: "Parlor palm", botanicalName: "Chamaedorea elegans",
            aliases: [],
            baselineIntervalDays: 8, lowLightMultiplier: 1.5,
            soilCheck: "Water when the top 1 inch of soil is dry. Dislikes soggy feet.",
            overwateringSigns: "Yellow fronds, root rot, brown tips.",
            underwateringSigns: "Brown, crispy tips and fronds.",
            winterNote: "Stretch to every 2-3 weeks in winter.",
            lowLightRating: .thrives, petToxicity: "Non-toxic to cats and dogs.",
            waterClass: .average
        ),
        PlantSpecies(
            id: "plant-peace-lily", commonName: "Peace lily", botanicalName: "Spathiphyllum spp.",
            aliases: [],
            baselineIntervalDays: 6, lowLightMultiplier: 1.4,
            soilCheck: "Water at the first slight droop, or when the top inch of soil is dry. Never let it sit in its saucer.",
            overwateringSigns: "Black leaf tips, yellowing, root rot.",
            underwateringSigns: "Dramatic whole-plant droop — it recovers quickly once watered.",
            winterNote: "Stretch to every 7-12 days in winter; blooms less.",
            lowLightRating: .tolerates, petToxicity: "Toxic to cats and dogs (oxalates; oral irritation).",
            waterClass: .moistureLover
        ),
        PlantSpecies(
            id: "plant-phalaenopsis-orchid", commonName: "Phalaenopsis orchid", botanicalName: "Phalaenopsis spp.",
            aliases: ["orchid", "moth orchid"],
            baselineIntervalDays: 7, lowLightMultiplier: 1.4,
            soilCheck: "Water when the bark is dry to the touch and the roots look silvery, not green.",
            overwateringSigns: "Limp yellow leaves, brown mushy roots.",
            underwateringSigns: "Wrinkled, leathery leaves; shriveled silver roots.",
            winterNote: "Stretch to every 10-14 days in winter.",
            lowLightRating: .tolerates, petToxicity: "Non-toxic to cats and dogs.",
            waterClass: .average
        ),
        PlantSpecies(
            id: "plant-pothos", commonName: "Pothos", botanicalName: "Epipremnum aureum",
            aliases: ["devil's ivy", "devils ivy"],
            baselineIntervalDays: 10, lowLightMultiplier: 1.5,
            soilCheck: "Water when the top 1-2 inches of soil are dry.",
            overwateringSigns: "Yellow leaves, black stems.",
            underwateringSigns: "Limp, wilted, crispy tips — recovers fast once watered.",
            winterNote: "Growth slows and it needs water less often in winter.",
            lowLightRating: .tolerates, petToxicity: "Toxic to cats and dogs (oxalates; oral irritation).",
            waterClass: .average
        ),
        PlantSpecies(
            id: "plant-rubber-plant", commonName: "Rubber plant", botanicalName: "Ficus elastica",
            aliases: ["rubber tree", "rubber fig"],
            baselineIntervalDays: 10, lowLightMultiplier: 1.5,
            soilCheck: "Water when the top 1-2 inches of soil are dry.",
            overwateringSigns: "Yellowing and dropping lower leaves, edema spots.",
            underwateringSigns: "Drooping, dry crispy edges.",
            winterNote: "Stretch to roughly 1.5-2x the interval in winter.",
            lowLightRating: .tolerates, petToxicity: "Mildly toxic to cats and dogs (latex sap).",
            waterClass: .average
        ),
        PlantSpecies(
            id: "plant-snake-plant", commonName: "Snake plant", botanicalName: "Dracaena trifasciata",
            aliases: ["sansevieria", "mother-in-law's tongue", "mother in laws tongue"],
            baselineIntervalDays: 17, lowLightMultiplier: 1.75,
            soilCheck: "Water only once the soil is fully dry.",
            overwateringSigns: "Mushy leaf bases, yellow and wrinkled leaves, rot.",
            underwateringSigns: "Wrinkled, leaning leaves.",
            winterNote: "Water every 4-6 weeks or less in winter.",
            lowLightRating: .tolerates, petToxicity: "Toxic to cats and dogs (saponins; mild GI upset).",
            waterClass: .light
        ),
        PlantSpecies(
            id: "plant-spider-plant", commonName: "Spider plant", botanicalName: "Chlorophytum comosum",
            aliases: [],
            baselineIntervalDays: 8, lowLightMultiplier: 1.5,
            soilCheck: "Water when the top 1 inch of soil is dry.",
            overwateringSigns: "Brown tips paired with soft roots.",
            underwateringSigns: "Pale, folded, faded leaves.",
            winterNote: "Stretch to every 10-14+ days in winter.",
            lowLightRating: .tolerates, petToxicity: "Non-toxic to cats and dogs.",
            waterClass: .average
        ),
        PlantSpecies(
            id: "plant-succulent", commonName: "Succulent (Echeveria-type)", botanicalName: "Echeveria spp.",
            aliases: ["succulent", "echeveria"],
            baselineIntervalDays: 17, lowLightMultiplier: 2.0,
            soilCheck: "Water only once the soil is fully dry, then soak the whole root ball and let it drain.",
            overwateringSigns: "Translucent, mushy leaves that drop at a touch.",
            underwateringSigns: "Wrinkled, deflated lower leaves.",
            winterNote: "Water every 3-6 weeks in winter, roughly monthly.",
            lowLightRating: .struggles, petToxicity: "Non-toxic to cats and dogs (echeveria).",
            waterClass: .light
        ),
        PlantSpecies(
            id: "plant-zz", commonName: "ZZ plant", botanicalName: "Zamioculcas zamiifolia",
            aliases: ["zz"],
            baselineIntervalDays: 20, lowLightMultiplier: 1.5,
            soilCheck: "Water when the soil is nearly fully dry.",
            overwateringSigns: "Yellow stems, mushy rhizomes.",
            underwateringSigns: "Leaflet drop, wrinkled stalks (rare — very drought-tolerant).",
            winterNote: "Water every 4-6 weeks in winter.",
            lowLightRating: .thrives, petToxicity: "Toxic to cats and dogs (oxalates; oral irritation).",
            waterClass: .light
        ),
    ]

    /// Lowercased search terms per species, parallel to `all` — common name
    /// first, then aliases. Built once so per-keystroke filtering doesn't
    /// re-lowercase the whole catalog.
    public static let searchIndex: [[String]] = all.map { sp in
        [sp.commonName.lowercased()] + sp.aliases.map { $0.lowercased() }
    }

    public static func species(id: String) -> PlantSpecies? {
        all.first { $0.id == id }
    }

    /// Best-effort lookup by free-text name (search field, or resolving a
    /// user-typed custom name back onto the curated research). Tries exact
    /// name/alias, then containment either direction, then a shared-word
    /// fallback — mirrors ExerciseInfo.catalogEntry(named:).
    public static func entry(named raw: String) -> PlantSpecies? {
        let q = raw.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return nil }

        if let exact = all.first(where: {
            $0.commonName.lowercased() == q || $0.aliases.contains(where: { $0.lowercased() == q })
        }) {
            return exact
        }

        if let contained = all.first(where: { sp in
            let n = sp.commonName.lowercased()
            if q.contains(n) || n.contains(q) { return true }
            return sp.aliases.contains { alias in
                let a = alias.lowercased()
                return q.contains(a) || a.contains(q)
            }
        }) {
            return contained
        }

        let qTokens = Set(q.split(separator: " ").map(String.init).filter { $0.count > 2 })
        guard !qTokens.isEmpty else { return nil }
        return all.first(where: { sp in
            let nTokens = Set(sp.commonName.lowercased().split(separator: " ").map(String.init))
            return !nTokens.isDisjoint(with: qTokens)
        })
    }

    /// Seeded interval for a species in a given room light level: baseline at
    /// bright light, +25% at medium, and the species' own low-light multiplier
    /// at low light (1.5x for most foliage, up to 2x for succulents/cacti).
    /// Clamped to a sane household range; fully editable afterward.
    public static func seededIntervalDays(for species: PlantSpecies, light: PlantLightLevel) -> Int {
        let multiplier: Double
        switch light {
        case .bright: multiplier = 1.0
        case .medium: multiplier = 1.25
        case .low:    multiplier = species.lowLightMultiplier
        }
        let days = Int((Double(species.baselineIntervalDays) * multiplier).rounded())
        return min(maxIntervalDays, max(minIntervalDays, days))
    }

    /// Suggested pour, in fl oz, for a water class at a given pot diameter.
    /// These are starting points, not precision doses — the app always also
    /// shows `drainageCopy` ("water until it runs from the drainage hole").
    public static func suggestedAmountFlOz(waterClass: PlantWaterClass, potDiameterInches: Int) -> Double {
        let table: [PlantWaterClass: [Int: Double]] = [
            .light:         [4: 2.5, 6: 7,  8: 14, 10: 28],
            .average:       [4: 5,   6: 14, 8: 32, 10: 60],
            .moistureLover: [4: 6.5, 6: 19, 8: 45, 10: 87],
        ]
        let byClass = table[waterClass] ?? table[.average]!
        return byClass[potDiameterInches] ?? byClass[6]!
    }

    /// Display string for a pour: whole numbers stay whole ("14"), fractions
    /// get one decimal ("2.5"). Shared by every amount readout and text field.
    public static func amountLabel(_ flOz: Double) -> String {
        flOz.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(flOz)) : String(format: "%.1f", flOz)
    }

    /// A stand-in species so a plant with no catalog match still runs the same
    /// seeded interval/amount math as a cataloged one — avoids duplicating the
    /// formulas above. Uses `customId` as its id, matching that constant's
    /// documented purpose. The care copy is generic-houseplant advice; the care
    /// card only renders for a genuinely cataloged species, so it is a fallback
    /// rather than something normally shown.
    public static func customSpecies(named raw: String) -> PlantSpecies {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        return PlantSpecies(
            id: customId, commonName: trimmed.isEmpty ? "Custom plant" : trimmed,
            botanicalName: "", aliases: [],
            baselineIntervalDays: 7, lowLightMultiplier: 1.5,
            soilCheck: "Check the top inch of soil; water when it's dry.",
            overwateringSigns: "Yellow leaves, mushy stems, or soil that stays wet for days.",
            underwateringSigns: "Drooping, dry, crispy leaves.",
            winterNote: "Most houseplants need water less often in winter.",
            lowLightRating: .tolerates,
            petToxicity: "Unknown — check the species before keeping pets nearby.",
            waterClass: .average
        )
    }
}
