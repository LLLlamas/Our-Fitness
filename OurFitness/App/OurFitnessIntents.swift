// App Intents for Apple Intelligence / Siri integration.
//
// Registering these lets Apple Intelligence learn the app's capabilities
// and proactively surface them to the user — e.g. "Log a meal in Our Fitness"
// appearing in Smart Stack, Focus filters, or Spotlight. Each intent opens
// the app via `openAppWhenRun: true`; tab deeplink routing is a future step.

import AppIntents

struct LogMealIntent: AppIntent {
    static var title: LocalizedStringResource = "Log a Meal"
    static var description = IntentDescription(
        "Opens Our Fitness to log what you ate.",
        categoryName: "Nutrition"
    )
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult { .result() }
}

struct LogWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource = "Log a Workout"
    static var description = IntentDescription(
        "Opens Our Fitness to the train tab.",
        categoryName: "Workouts"
    )
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult { .result() }
}

struct CheckTodayIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Today's Progress"
    static var description = IntentDescription(
        "Opens Our Fitness to see today's macros and steps.",
        categoryName: "Progress"
    )
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult { .result() }
}

// MARK: - Shortcuts provider — auto-registers phrases with Siri

struct OurFitnessShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogMealIntent(),
            phrases: [
                "Log a meal in \(.applicationName)",
                "Add food to \(.applicationName)",
                "Track what I ate in \(.applicationName)",
            ],
            shortTitle: "Log meal",
            systemImageName: "fork.knife"
        )
        AppShortcut(
            intent: LogWorkoutIntent(),
            phrases: [
                "Log a workout in \(.applicationName)",
                "Track my workout in \(.applicationName)",
                "Open train tab in \(.applicationName)",
            ],
            shortTitle: "Log Workout",
            systemImageName: "figure.walk"
        )
        AppShortcut(
            intent: CheckTodayIntent(),
            phrases: [
                "Check my progress in \(.applicationName)",
                "Show today in \(.applicationName)",
                "How am I doing in \(.applicationName)",
            ],
            shortTitle: "Today's Progress",
            systemImageName: "chart.bar.fill"
        )
    }
}
