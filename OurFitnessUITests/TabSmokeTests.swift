// The only test in this project that launches the real app.
//
// `OurFitnessTests` is hostless and compiles `Domain/` directly, which makes it
// fast but means ~500 passing tests say nothing about whether a tab opens. Every
// SwiftUI refactor so far has been "compiles, therefore presumed fine". This
// closes that gap at the cheapest useful level: open each tab, confirm the app
// is still running and showing something.
//
// Deliberately shallow. It asserts the app survives navigation, not that any
// particular pixel is right — a brittle UI test that fails on copy changes gets
// deleted, and then there is no UI coverage at all again.

import XCTest

final class TabSmokeTests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Fresh install lands on onboarding. Fill the one required field and
    /// continue, so the tabs are reachable.
    private func completeOnboardingIfPresent(_ app: XCUIApplication) {
        let createButton = app.buttons["Create profile"]
        guard createButton.waitForExistence(timeout: 10) else { return }   // already onboarded

        let nameField = app.textFields["e.g. Lorenzo"]
        if nameField.waitForExistence(timeout: 5) {
            nameField.tap()
            nameField.typeText("Test")
        }
        // The button sits below the fold on smaller devices.
        if !createButton.isHittable { app.swipeUp() }
        createButton.tap()
    }

    func test_every_tab_opens_without_crashing() {
        let app = XCUIApplication()
        app.launch()
        completeOnboardingIfPresent(app)

        // Tab bar is the signal that onboarding is behind us.
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15),
                      "No tab bar after onboarding — the app never reached its main shell.")

        for name in ["Today", "Meals", "Train", "Reminders", "Progress"] {
            let tab = app.tabBars.buttons[name]
            XCTAssertTrue(tab.waitForExistence(timeout: 10), "Tab '\(name)' is missing.")
            tab.tap()

            // `state == .runningForeground` is the real assertion: a SwiftUI
            // crash on tab entry drops the app out of the foreground, and that
            // is exactly the failure mode the hostless suite cannot see.
            XCTAssertEqual(app.state, .runningForeground,
                           "App left the foreground after opening '\(name)' — likely a crash.")
            XCTAssertTrue(app.staticTexts.count > 0, "'\(name)' rendered no text at all.")
        }
    }

    /// The Meals history button replaced a calendar picker. Opening it exercises
    /// the new MealHistorySheet / MealHistoryList path.
    func test_meals_history_sheet_opens() {
        let app = XCUIApplication()
        app.launch()
        completeOnboardingIfPresent(app)

        guard app.tabBars.buttons["Meals"].waitForExistence(timeout: 15) else {
            return XCTFail("Never reached the tab bar.")
        }
        app.tabBars.buttons["Meals"].tap()

        // Matched on the SF Symbol identifier, not the label: `.tactile(.pill)`
        // applies `.textCase(.uppercase)`, which uppercases the accessibility
        // label too ("MEAL HISTORY"), so a label match is case-fragile.
        let history = app.buttons["clock.arrow.circlepath"]
        guard history.waitForExistence(timeout: 10) else {
            return XCTFail("Meals has no 'Meal history' button — the day-history entry point is gone.")
        }
        history.tap()

        XCTAssertTrue(app.staticTexts["Meal history"].waitForExistence(timeout: 5),
                      "History sheet did not present.")
        XCTAssertEqual(app.state, .runningForeground)
    }
}
