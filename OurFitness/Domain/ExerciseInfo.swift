// Research-backed exercise metadata for the Build mode exercise list.
// Muscle groups, physiological benefits, MET values, and rep tempo.
//
// Sources:
//   Ainsworth BE et al. "2011 Compendium of Physical Activities." Med Sci Sports Exerc, 2011.
//   NSCA Essentials of Strength Training & Conditioning. 4th ed. (Haff & Triplett, 2016).
//   Schoenfeld BJ. "The Mechanisms of Muscle Hypertrophy." J Strength Cond Res, 2010.
//   Contreras B et al. "A comparison of gluteus maximus EMG activity..." J Strength Cond Res, 2015.
//   McGill SM. Low Back Disorders. 2nd ed. Human Kinetics, 2007.
//   Yang J et al. "Association between push-up exercise capacity and cardiovascular events." JAMA, 2019.
//   Leong DP et al. "Prognostic value of grip strength." Lancet, 2015.

import Foundation

public enum ExerciseInfo {

    public struct Meta: Sendable {
        /// Primary movers in order of activation.
        public let muscleGroups: [String]
        /// Stabilisers and synergists.
        public let secondaryMuscles: [String]
        /// 2–4 evidence-based benefit statements.
        public let benefits: [String]
        /// MET value from Ainsworth 2011 Compendium. Used for calorie estimation.
        public let met: Double
        /// Assumed seconds per rep for calorie math. Slower = more TUT = more accurate.
        public let secondsPerRep: Double
    }

    /// Returns research-backed metadata for an exercise, falling back to category
    /// defaults when the name is not in the library.
    public static func meta(for exercise: ExerciseDTO) -> Meta {
        if let named = namedMeta(exercise.name.lowercased()) { return named }
        return categoryDefaults(exercise.category, hasLoad: (exercise.loadLb ?? 0) > 0)
    }

    /// Whether this exercise has hand-curated, citation-backed metadata.
    /// Custom / user-invented exercises return `false` and are candidates for
    /// on-device AI enrichment (see Services/ExerciseInsightService).
    public static func hasCuratedMeta(for exercise: ExerciseDTO) -> Bool {
        namedMeta(exercise.name.lowercased()) != nil
    }

    // MARK: - Plain-English muscle names

    /// Anatomical muscle name → everyday gloss. Used to append a plain-English
    /// "(what/where it is)" so non-experts understand the muscle list. Keep keys
    /// lowercase; matching is by substring so "Lats" and "Latissimus dorsi" both hit.
    private static let muscleGlossary: [(key: String, gloss: String)] = [
        ("latissimus",        "the broad muscles down your back"),
        ("lats",              "the broad muscles down your back that make the V-shape"),
        ("pectoral",          "chest"),
        ("anterior delt",     "front of your shoulders"),
        ("lateral delt",      "sides of your shoulders"),
        ("rear delt",         "back of your shoulders"),
        ("deltoid",           "shoulders"),
        ("triceps",           "back of your upper arm"),
        ("biceps brachii",    "front of your upper arm"),
        ("brachialis",        "a muscle just under the biceps"),
        ("brachioradialis",   "a forearm muscle"),
        ("forearm",           "forearm"),
        ("rhomboid",          "between your shoulder blades"),
        ("teres major",       "a small muscle under the armpit"),
        ("trapezius",         "the muscle from neck to shoulders"),
        ("upper trap",        "the muscle from neck to shoulders"),
        ("middle trap",       "mid-upper back"),
        ("levator scapulae",  "side of your neck"),
        ("serratus anterior", "finger-like muscles along your ribs"),
        ("coracobrachialis",  "a small front-of-shoulder muscle"),
        ("rotator cuff",      "the small muscles that steady your shoulder"),
        ("scapular",          "shoulder-blade muscles"),
        ("quadriceps",        "front of your thighs"),
        ("quads",             "front of your thighs"),
        ("hamstring",         "back of your thighs"),
        ("gluteus maximus",   "your main butt muscle"),
        ("glute",             "your butt/seat muscles"),
        ("adductor",          "inner thighs"),
        ("hip flexor",        "front of your hips"),
        ("hip stabil",        "muscles that steady your hips"),
        ("erector spinae",    "the muscles running up either side of your spine"),
        ("transverse abdominis", "the deep core muscle that wraps your waist like a belt"),
        ("rectus abdominis",  "the \u{201C}six-pack\u{201D} muscle, the top layer of your abs"),
        ("oblique",           "the sides of your waist"),
        ("gastrocnemius",     "the bulky calf muscle"),
        ("soleus",            "the deep calf muscle"),
        ("tibialis",          "a shin muscle"),
        ("peronei",           "outer lower-leg muscles"),
        ("anconeus",          "a small muscle at the elbow"),
    ]

    /// Appends a plain-English gloss to an anatomical muscle name, e.g.
    /// "Rectus abdominis" → "Rectus abdominis (the “six-pack” muscle…)".
    /// Leaves names that already carry a parenthetical, or that have no known
    /// gloss, untouched.
    public static func plainName(forMuscle raw: String) -> String {
        guard !raw.contains("(") else { return raw }   // already annotated
        let lower = raw.lowercased()
        // Longest key first so "gluteus maximus" wins over "glute".
        if let match = muscleGlossary
            .sorted(by: { $0.key.count > $1.key.count })
            .first(where: { lower.contains($0.key) }) {
            return "\(raw) (\(match.gloss))"
        }
        return raw
    }

    /// Glosses a list of muscle names, joined for display.
    public static func plainMuscleList(_ muscles: [String], separator: String = " · ") -> String {
        muscles.map(plainName(forMuscle:)).joined(separator: separator)
    }

    // MARK: - Named library

    private static func namedMeta(_ lower: String) -> Meta? {

        // Pull-ups / Chin-ups
        if lower.hasPrefix("pull") || lower.hasPrefix("chin") || lower.contains("lat pull") {
            let isChin = lower.contains("chin")
            return Meta(
                muscleGroups: ["Lats", isChin ? "Biceps (supinated emphasis)" : "Biceps", "Rear delts"],
                secondaryMuscles: ["Core", "Rhomboids", "Teres major", "Scapular retractors"],
                benefits: [
                    "Lats are the primary driver of back width — the V-taper comes from here.",
                    "Elbow flexion under full bodyload adds real bicep thickness over time.",
                    "Scapular retraction trained here protects the shoulder joint long-term.",
                    "NSCA research links pulling strength to reduced lower-back injury risk."
                ],
                met: 8.0, secondsPerRep: 4.0
            )
        }

        // Push-ups (bodyweight)
        if lower.hasPrefix("push") && !lower.contains("press") {
            return Meta(
                muscleGroups: ["Pectorals", "Anterior delts", "Triceps"],
                secondaryMuscles: ["Core", "Serratus anterior"],
                benefits: [
                    "Trains chest, shoulders, and triceps simultaneously — high cal burn per set.",
                    "Yang et al. (JAMA 2019): push-up capacity was a significant inverse predictor of 10-year cardiovascular events in men.",
                    "Serratus anterior activation protects the shoulder blade against impingement.",
                    "No equipment, fully scalable — incline reduces load, decline or feet-elevated increases it."
                ],
                met: 8.0, secondsPerRep: 2.5
            )
        }

        // Bench press
        if lower.contains("bench") {
            return Meta(
                muscleGroups: ["Pectorals", "Anterior delts", "Triceps"],
                secondaryMuscles: ["Serratus anterior", "Coracobrachialis", "Core"],
                benefits: [
                    "Horizontal push — primary driver of pec thickness and width.",
                    "Triceps are maximally loaded in lockout, adding direct arm mass.",
                    "Serratus anterior activation in the press protects the shoulder girdle.",
                    "Upper-body pressing strength tracks with metabolic rate and functional independence."
                ],
                met: 5.0, secondsPerRep: 3.0
            )
        }

        // Chest fly / pec fly (chest isolation). Excludes "reverse fly" (rear delt —
        // handled in the face-pull branch below).
        if lower.contains("fly") && !lower.contains("reverse") {
            return Meta(
                muscleGroups: ["Pectorals"],
                secondaryMuscles: ["Anterior delts", "Biceps"],
                benefits: [
                    "Isolates the chest through horizontal adduction — a deeper stretch than the bench press loads directly.",
                    "Adds chest volume without taxing the triceps, so it pairs well after pressing work.",
                    "Keep the elbows softly bent and the weight moderate — flyes load the shoulder at full stretch."
                ],
                met: 3.5, secondsPerRep: 3.0
            )
        }

        // Overhead press / shoulder press
        if lower.contains("overhead") || lower.contains("ohp") ||
           lower.contains("shoulder press") || lower.contains("military") ||
           (lower.contains("press") && !lower.contains("bench") && !lower.contains("leg") && !lower.contains("chest")) {
            return Meta(
                muscleGroups: ["Anterior delts", "Triceps", "Upper traps"],
                secondaryMuscles: ["Lateral delts", "Rotator cuff", "Core", "Serratus anterior"],
                benefits: [
                    "Vertical push — builds rounded shoulder width and anterior delt mass.",
                    "Stabilises the thoracic spine under overhead load, improving posture.",
                    "Tricep lockout carryover: stronger OHP reliably means a stronger bench.",
                    "Overhead pressing ability predicts athletic overhead performance across sports."
                ],
                met: 5.0, secondsPerRep: 3.0
            )
        }

        // Lateral / front raise (shoulder isolation)
        if lower.contains("lateral raise") || lower.contains("lat raise")
            || lower.contains("side raise") || lower.contains("front raise")
            || lower.contains("delt raise") {
            let isFront = lower.contains("front")
            return Meta(
                muscleGroups: isFront ? ["Anterior delts"] : ["Lateral delts"],
                secondaryMuscles: ["Upper traps", "Rotator cuff"],
                benefits: [
                    isFront
                        ? "Targets the front of the shoulder through flexion — fills out the cap from the front."
                        : "Targets the side delts — the muscle that creates shoulder width and the round, capped look.",
                    "Pure isolation: light weight with strict control beats heavy swinging here.",
                    "Balanced delt development improves posture and shoulder-joint stability."
                ],
                met: 3.5, secondsPerRep: 2.5
            )
        }

        // Squat
        if lower.contains("squat") {
            let isFront = lower.contains("front") || lower.contains("goblet")
            return Meta(
                muscleGroups: [isFront ? "Quads (front emphasis)" : "Quads", "Glutes", "Hamstrings"],
                secondaryMuscles: ["Erector spinae", "Core", "Adductors", "Calves"],
                benefits: [
                    "Recruits the largest muscle groups in the body — highest anabolic response per set of any exercise.",
                    "Glute and quad mass raises your resting metabolic rate, burning more calories at rest.",
                    "Properly loaded squats strengthen knee and hip joint integrity over time.",
                    "Squat strength in midlife is a strong predictor of functional independence and longevity."
                ],
                met: 5.0, secondsPerRep: 3.0
            )
        }

        // Leg press / leg extension / leg curl (machines). Placed before the tricep
        // "extension" branch so "leg extension" reads as quads, not triceps.
        if lower.contains("leg press") || lower.contains("leg extension")
            || lower.contains("leg curl") || lower.contains("hamstring curl") {
            let isCurl = lower.contains("curl")
            let isExtension = lower.contains("extension")
            return Meta(
                muscleGroups: isCurl ? ["Hamstrings"]
                    : (isExtension ? ["Quads"] : ["Quads", "Glutes", "Hamstrings"]),
                secondaryMuscles: isCurl ? ["Calves"] : ["Adductors", "Calves"],
                benefits: [
                    isCurl
                        ? "Isolates the hamstrings through knee flexion — balances the quad-dominant work most lower bodies get."
                        : (isExtension
                            ? "Isolates the quads with no balance demand — useful for adding knee-extension volume after compound lifts."
                            : "Machine pressing loads the quads and glutes on a fixed path — easy to progress and low on technique risk."),
                    "Machines let you push close to failure safely without a spotter, which drives hypertrophy.",
                    "Stronger legs raise resting metabolic rate and protect the knee and hip joints over time."
                ],
                met: lower.contains("leg press") ? 5.0 : 3.5, secondsPerRep: 3.0
            )
        }

        // Deadlift (all variants)
        if lower.contains("deadlift") || lower.contains("rdl") || lower.contains("romanian") || lower.contains("sumo") {
            return Meta(
                muscleGroups: ["Hamstrings", "Glutes", "Erector spinae"],
                secondaryMuscles: ["Lats", "Traps", "Core", "Grip/Forearms"],
                benefits: [
                    "Posterior chain king — hamstrings, glutes, and back all trained in one pull.",
                    "McGill (2007): deadlift training significantly reduces chronic lower-back pain incidence.",
                    "Grip strength built here predicts all-cause mortality better than blood pressure (Leong et al., Lancet 2015).",
                    "The hip-hinge pattern transfers directly to every loaded daily movement."
                ],
                met: 6.0, secondsPerRep: 4.0
            )
        }

        // Row (any variant)
        if lower.contains("row") {
            return Meta(
                muscleGroups: ["Rhomboids", "Middle traps", "Rear delts", "Biceps"],
                secondaryMuscles: ["Erector spinae", "Core", "Lats (lower rows)"],
                benefits: [
                    "Horizontal pull directly counteracts the forward-posture effects of bench/press work.",
                    "Scapular retraction trained here reduces shoulder impingement risk (Cools et al., 2007).",
                    "Rear delt mass improves overhead mobility and rotator cuff health.",
                    "Consistent row volume correlates with reduced neck and upper-back pain."
                ],
                met: 5.0, secondsPerRep: 3.0
            )
        }

        // Bicep curl
        if lower.contains("curl") && !lower.contains("leg") {
            return Meta(
                muscleGroups: ["Biceps brachii", "Brachialis"],
                secondaryMuscles: ["Brachioradialis", "Forearms"],
                benefits: [
                    "Directly targets elbow flexion for arm thickness and bicep peak.",
                    "The brachialis sits under the bicep — developing it pushes the bicep visually higher.",
                    "Supinated (underhand) grip maximises long-head stretch at the bottom of the ROM.",
                    "Schoenfeld (2016): moderate to high reps equally effective as heavy reps for bicep hypertrophy."
                ],
                met: 3.5, secondsPerRep: 3.0
            )
        }

        // Tricep work
        if lower.contains("tricep") || lower.contains("extension") ||
           lower.contains("pushdown") || lower.contains("skull") ||
           (lower.contains("dip") && !lower.contains("hip")) {
            return Meta(
                muscleGroups: ["Triceps brachii (all 3 heads)"],
                secondaryMuscles: ["Anconeus", "Rear delts (dips)"],
                benefits: [
                    "Triceps account for ~65% of upper-arm mass — largest contribution to arm size.",
                    "Overhead extensions maximally load the long head, which crosses the shoulder joint.",
                    "Lockout strength improves directly — a stronger tricep means a stronger bench and press.",
                    "Dips additionally load anterior delts and pecs for compound pushing volume."
                ],
                met: 5.0, secondsPerRep: 3.0
            )
        }

        // Lunge / split squat
        if lower.contains("lunge") || lower.contains("split squat") ||
           lower.contains("step up") || lower.contains("step-up") {
            return Meta(
                muscleGroups: ["Quads", "Glutes"],
                secondaryMuscles: ["Hamstrings", "Hip stabilisers", "Core"],
                benefits: [
                    "Unilateral loading corrects left-right strength imbalances invisible in bilateral squats.",
                    "Higher glute activation per unit of load than a bilateral back squat.",
                    "Trains single-leg stability — associated with reduced ACL and ankle injury rates.",
                    "Functional carryover: every stair climb and every running stride is a single-leg squat."
                ],
                met: 4.0, secondsPerRep: 3.0
            )
        }

        // Hip thrust / glute bridge
        if lower.contains("hip thrust") || lower.contains("glute bridge") ||
           lower.contains("hip hinge") || lower.contains("thrust") {
            return Meta(
                muscleGroups: ["Gluteus maximus", "Hamstrings"],
                secondaryMuscles: ["Core", "Adductors"],
                benefits: [
                    "Contreras et al. (2015): hip thrust produces the highest gluteus maximus EMG of any exercise tested.",
                    "Horizontal force production from this pattern improves sprint speed and jump height.",
                    "Low spinal compressive load — accessible even with lower-back issues.",
                    "Strong glutes reduce anterior pelvic tilt and chronic lower-back pain."
                ],
                met: 4.0, secondsPerRep: 3.0
            )
        }

        // Reverse plank (posterior-chain hold) — before the plank branch so it does
        // not inherit the anterior-core plank muscle list.
        if lower.contains("reverse plank") {
            return Meta(
                muscleGroups: ["Glutes", "Hamstrings", "Erector spinae"],
                secondaryMuscles: ["Rear delts", "Core"],
                benefits: [
                    "Trains the whole back of the body in one hold — glutes, hamstrings, and spinal erectors together.",
                    "A direct counter to all-day sitting and the forward, hunched posture it builds.",
                    "No equipment, low joint stress — hold for time and progress the seconds."
                ],
                met: 3.8, secondsPerRep: 3.0
            )
        }

        // Wall sit (isometric quad/glute hold)
        if lower.contains("wall sit") {
            return Meta(
                muscleGroups: ["Quads", "Glutes"],
                secondaryMuscles: ["Hamstrings", "Calves"],
                benefits: [
                    "Builds quad and glute endurance under constant tension — a joint-friendly way to load the legs.",
                    "No equipment and easy to scale: hold longer or sink lower.",
                    "Isometric leg holds are associated with improved knee stability."
                ],
                met: 4.0, secondsPerRep: 3.0
            )
        }

        // Dead hang (grip + shoulder decompression hold)
        if lower.contains("dead hang") || lower.contains("bar hang") {
            return Meta(
                muscleGroups: ["Forearms/Grip", "Lats"],
                secondaryMuscles: ["Shoulders", "Core"],
                benefits: [
                    "Builds grip and forearm strength — grip strongly correlates with overall strength and healthy aging.",
                    "Decompresses the spine and stretches the shoulders and lats after pressing work.",
                    "A simple progression toward your first pull-up: hold for time, then add reps."
                ],
                met: 4.0, secondsPerRep: 3.0
            )
        }

        // L-sit (anterior-core + hip-flexor hold)
        if lower.contains("l-sit") || lower.contains("l sit") {
            return Meta(
                muscleGroups: ["Rectus abdominis", "Hip flexors"],
                secondaryMuscles: ["Triceps", "Quads", "Shoulders"],
                benefits: [
                    "One of the most demanding ab holds — braces the core hard while the hip flexors hold the legs out straight.",
                    "Also loads the triceps and shoulders to stay propped up, training the whole front line.",
                    "Scale down with bent knees or feet supported, then work toward straight legs."
                ],
                met: 4.0, secondsPerRep: 3.0
            )
        }

        // Core / plank / abs
        if lower.contains("plank") || lower.contains("hollow") ||
           lower.contains("crunch") || lower.contains("sit-up") || lower.contains("sit up") ||
           lower.contains(" ab ") || lower.hasSuffix("abs") {
            return Meta(
                muscleGroups: ["Transverse abdominis", "Rectus abdominis"],
                secondaryMuscles: ["Obliques", "Erector spinae (plank)", "Hip flexors"],
                benefits: [
                    "Anti-extension and anti-rotation strength transfers directly to every heavy compound lift.",
                    "McGill's Big-3 (curl-up, bird-dog, side bridge) shown to halve chronic LBP recurrence.",
                    "Intra-abdominal pressure generated by bracing protects the lumbar spine under load.",
                    "Core strength improves power transfer from the lower body to the upper body."
                ],
                met: 3.8, secondsPerRep: 3.0
            )
        }

        // Calf raise
        if lower.contains("calf") {
            return Meta(
                muscleGroups: ["Gastrocnemius", "Soleus"],
                secondaryMuscles: ["Tibialis posterior", "Peronei"],
                benefits: [
                    "Calf strength is the primary ankle stabiliser for walking, running, and jumping.",
                    "The soleus is slow-twitch dominant — responds best to higher reps (15–30+).",
                    "Progressive calf raises reduce Achilles tendon injury risk and improve jump height.",
                    "Weak calves correlate with increased risk of falls and ankle sprains."
                ],
                met: 3.5, secondsPerRep: 2.5
            )
        }

        // Face pull / rear delt fly
        if lower.contains("face pull") || lower.contains("facepull") ||
           lower.contains("rear delt") || lower.contains("reverse fly") {
            return Meta(
                muscleGroups: ["Rear delts", "Rotator cuff (external rotators)", "Rhomboids"],
                secondaryMuscles: ["Middle traps", "Biceps"],
                benefits: [
                    "Corrective for internal rotation imbalance created by heavy bench and press volume.",
                    "External rotation pattern directly strengthens the rotator cuff against impingement.",
                    "One of the highest-yield movements for long-term shoulder health per PT research.",
                    "Rear delt mass visually rounds the shoulder from the side and back."
                ],
                met: 3.5, secondsPerRep: 3.0
            )
        }

        // Shrug / trap
        if lower.contains("shrug") || lower.contains("upright row") {
            return Meta(
                muscleGroups: ["Upper traps", "Levator scapulae"],
                secondaryMuscles: ["Middle traps", "Rhomboids"],
                benefits: [
                    "Upper trap development creates shoulder width and neck/shoulder mass.",
                    "Scapular elevation strength supports overhead positioning and reduces impingement.",
                    "Grip strength training bonus with heavy-loaded shrugs."
                ],
                met: 4.0, secondsPerRep: 2.5
            )
        }

        return nil
    }

    // MARK: - Category defaults

    private static func categoryDefaults(_ cat: ExerciseCategory, hasLoad: Bool) -> Meta {
        switch cat {
        case .compound:
            return Meta(
                muscleGroups: ["Multiple major muscle groups"],
                secondaryMuscles: ["Core", "Stabilisers"],
                benefits: [
                    "Compound movements work the most muscle at once — the biggest bang for your time.",
                    "More muscle worked per set means more strength and size built per session.",
                    "Great time-efficiency: one lift trains several muscle groups together."
                ],
                met: 5.5, secondsPerRep: 3.5
            )
        case .isolation:
            return Meta(
                muscleGroups: ["Targeted muscle group"],
                secondaryMuscles: [],
                benefits: [
                    "Directly trains a lagging muscle without loading stabilisers.",
                    "Useful for specialisation after compound volume is set.",
                    "Higher rep ranges (12–25) are equally effective for hypertrophy at this category."
                ],
                met: 3.5, secondsPerRep: 3.0
            )
        case .bodyweight:
            return Meta(
                muscleGroups: ["Body-dependent major groups"],
                secondaryMuscles: ["Core"],
                benefits: [
                    "No equipment needed. High reps develop muscular endurance and density.",
                    "Bodyweight movement maintains motor patterns and joint mobility over time."
                ],
                met: hasLoad ? 5.0 : 4.0, secondsPerRep: 3.0
            )
        case .cardio:
            return Meta(
                muscleGroups: ["Cardiovascular system", "Lower body"],
                secondaryMuscles: ["Core"],
                benefits: [
                    "Zone-2 cardio raises HDL and lowers triglycerides measurably within 8–12 weeks.",
                    "Each session improves insulin sensitivity for 24–48 hours post-exercise."
                ],
                met: 7.0, secondsPerRep: 1.0
            )
        case .mobility:
            return Meta(
                muscleGroups: ["Joints", "Connective tissue"],
                secondaryMuscles: [],
                benefits: [
                    "Improves active range of motion and reduces injury risk at high loads.",
                    "Mobility work combined with progressive loading extends joint longevity."
                ],
                met: 2.5, secondsPerRep: 3.0
            )
        }
    }
}
