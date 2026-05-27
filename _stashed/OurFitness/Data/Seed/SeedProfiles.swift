// Legacy seed profiles. Kept compiling for reference; no longer invoked by
// Seeder. Multi-profile creation now goes through ProfileCreationView.

import Foundation

public enum SeedProfiles {

    public static let buildId = UUID(uuidString: "00000000-0000-0000-0000-0000000B0000")!
    public static let circuitId = UUID(uuidString: "00000000-0000-0000-0000-0000000E5E70")!

    public static let all: [ProfileDTO] = [build, circuit]

    public static let build: ProfileDTO = {
        let vitals = Targets.ProfileVitals(
            sex: .male, weightLb: 130, heightIn: 67, age: 30, activity: .active
        )
        return ProfileDTO(
            id: buildId,
            name: "Build",
            mode: .build,
            sex: vitals.sex,
            heightIn: vitals.heightIn,
            weightLb: vitals.weightLb,
            age: vitals.age,
            activity: vitals.activity,
            lowAppetite: true,
            restrictions: ["peanut", "tree-nut"],
            computedTargets: Targets.compute(mode: .build, vitals: vitals)
        )
    }()

    public static let circuit: ProfileDTO = {
        let vitals = Targets.ProfileVitals(
            sex: .female, weightLb: 175, heightIn: 64, age: 50, activity: .light
        )
        return ProfileDTO(
            id: circuitId,
            name: "Circuit",
            mode: .circuit,
            sex: vitals.sex,
            heightIn: vitals.heightIn,
            weightLb: vitals.weightLb,
            age: vitals.age,
            activity: vitals.activity,
            lowAppetite: false,
            restrictions: [],
            computedTargets: Targets.compute(mode: .circuit, vitals: vitals)
        )
    }()
}
