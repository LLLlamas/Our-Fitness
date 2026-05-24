// Starter programs. One per mode minimum.

import Foundation

public enum SeedPrograms {

    private static func spec(_ ex: String, sets: Int, _ bottom: Int, _ top: Int,
                             rpe: Double? = nil, rest: Int? = nil) -> ProgramSetSpec {
        ProgramSetSpec(exerciseId: ex, sets: sets, repsBottom: bottom, repsTop: top,
                       rpeCap: rpe, restSeconds: rest)
    }

    public static let all: [ProgramDTO] = [
        ProgramDTO(
            id: "prog-build-upper-lower",
            name: "Build · Upper / Lower (4-day)",
            modeFit: [.build],
            schedule: [
                ProgramDayDTO(label: "Upper A", blocks: [
                    spec("ex-bench-press",     sets: 4, 6, 8, rest: 150),
                    spec("ex-barbell-row",     sets: 4, 6, 10, rest: 150),
                    spec("ex-db-incline-bench", sets: 3, 8, 12, rest: 120),
                    spec("ex-lat-pulldown",    sets: 3, 10, 12, rest: 90),
                    spec("ex-db-curl",         sets: 3, 10, 15, rest: 75),
                    spec("ex-tricep-pushdown", sets: 3, 10, 15, rest: 75),
                ]),
                ProgramDayDTO(label: "Lower A", blocks: [
                    spec("ex-back-squat",   sets: 4, 5, 8, rest: 180),
                    spec("ex-rdl",          sets: 3, 6, 10, rest: 150),
                    spec("ex-leg-press",    sets: 3, 10, 12, rest: 120),
                    spec("ex-leg-curl",     sets: 3, 10, 15, rest: 90),
                    spec("ex-calf-raise",   sets: 4, 10, 15, rest: 60),
                ]),
                ProgramDayDTO(label: "Upper B", blocks: [
                    spec("ex-overhead-press", sets: 4, 5, 8, rest: 150),
                    spec("ex-pullup",         sets: 4, 5, 10, rest: 120),
                    spec("ex-db-bench",       sets: 3, 8, 12, rest: 120),
                    spec("ex-cable-row",      sets: 3, 10, 12, rest: 90),
                    spec("ex-lateral-raise",  sets: 3, 12, 20, rest: 60),
                    spec("ex-face-pull",      sets: 3, 12, 20, rest: 60),
                ]),
                ProgramDayDTO(label: "Lower B", blocks: [
                    spec("ex-deadlift",      sets: 3, 3, 6, rest: 240),
                    spec("ex-front-squat",   sets: 3, 6, 10, rest: 150),
                    spec("ex-hip-thrust",    sets: 3, 8, 12, rest: 120),
                    spec("ex-leg-extension", sets: 3, 10, 15, rest: 90),
                    spec("ex-plank",         sets: 3, 1, 1, rest: 60),
                ]),
            ],
            progression: .doubleProgression,
            notes: "Hypertrophy bias. 4 sessions/week with hoops on off-days. Push hard, eat harder."
        ),

        ProgramDTO(
            id: "prog-reset-strength-cardio",
            name: "Reset · Strength + Zone 2 (5-day)",
            modeFit: [.reset],
            schedule: [
                ProgramDayDTO(label: "Full Body A", blocks: [
                    spec("ex-db-goblet-squat", sets: 3, 10, 12, rpe: 7, rest: 120),
                    spec("ex-db-bench",        sets: 3, 8, 12, rpe: 7, rest: 120),
                    spec("ex-db-row",          sets: 3, 8, 12, rpe: 7, rest: 120),
                    spec("ex-glute-bridge",    sets: 3, 12, 15, rest: 60),
                    spec("ex-plank",           sets: 3, 1, 1, rest: 60),
                ]),
                ProgramDayDTO(label: "Zone 2 Cardio", blocks: [
                    spec("ex-zone2-walk", sets: 1, 1, 1),
                ]),
                ProgramDayDTO(label: "Full Body B", blocks: [
                    spec("ex-rdl",                sets: 3, 8, 10, rpe: 7, rest: 120),
                    spec("ex-db-shoulder-press",  sets: 3, 8, 12, rpe: 7, rest: 120),
                    spec("ex-lat-pulldown",       sets: 3, 10, 12, rpe: 7, rest: 120),
                    spec("ex-db-walking-lunge",   sets: 3, 10, 12, rest: 90),
                    spec("ex-face-pull",          sets: 3, 12, 20, rest: 60),
                ]),
                ProgramDayDTO(label: "Zone 2 Cardio", blocks: [
                    spec("ex-zone2-bike", sets: 1, 1, 1),
                ]),
                ProgramDayDTO(label: "Long Zone 2", blocks: [
                    spec("ex-incline-treadmill", sets: 1, 1, 1),
                ]),
            ],
            progression: .rpeBased,
            notes: "2 full-body strength + 3 zone-2 cardio. RPE cap 7 keeps recovery sustainable in a deficit."
        ),
    ]
}
