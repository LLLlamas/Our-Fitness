// Two fixed profiles for the two humans this app exists for.
// Stable IDs so both devices reference the same logical profile after a future CloudKit sync.
// Idempotent: re-running the seeder never overwrites edited vitals.

import Foundation

public enum SeedProfiles {

    public static let buildId = UUID(uuidString: "00000000-0000-0000-0000-0000000B0000")!
    public static let resetId = UUID(uuidString: "00000000-0000-0000-0000-0000000E5E70")!

    public static let all: [ProfileDTO] = [build, reset]

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

    public static let reset: ProfileDTO = {
        let vitals = Targets.ProfileVitals(
            sex: .female, weightLb: 175, heightIn: 64, age: 50, activity: .light
        )
        return ProfileDTO(
            id: resetId,
            name: "Reset",
            mode: .reset,
            sex: vitals.sex,
            heightIn: vitals.heightIn,
            weightLb: vitals.weightLb,
            age: vitals.age,
            activity: vitals.activity,
            lowAppetite: false,
            restrictions: [],
            computedTargets: Targets.compute(mode: .reset, vitals: vitals)
        )
    }()
}
