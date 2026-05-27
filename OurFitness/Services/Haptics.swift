// Central haptic dispatcher.
// Two patterns:
//   1. Imperative — `Haptics.success()` from anywhere on MainActor (after a write completes).
//   2. Declarative — `.sensoryFeedback(_:trigger:)` on a view (preferred for state-driven feedback).
//
// Keep the vocabulary small. Too many distinct haptics = noise.
//
// Vocabulary:
//   tap     — every button press (light, ubiquitous)
//   bump    — incremental controls (a logged set, a slot switch)
//   success — goal hit, set logged that beat a PR
//   warn    — destructive confirm, cap breach
//   select  — picker/segmented change

import UIKit

@MainActor
public enum Haptics {

    // Generators are reused (cheap; iOS recommends pre-warming for snappier response).
    private static let light  = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let rigid  = UIImpactFeedbackGenerator(style: .rigid)
    private static let notif  = UINotificationFeedbackGenerator()
    private static let select = UISelectionFeedbackGenerator()

    /// Light press confirmation. Default for every button.
    public static func tap()     { light.prepare();  light.impactOccurred(intensity: 0.6) }
    /// Discrete increment (a logged set, a slot switch).
    public static func bump()    { medium.prepare(); medium.impactOccurred(intensity: 0.7) }
    /// Goal hit, PR beaten, session finished — meaningful win.
    public static func success() { notif.prepare();  notif.notificationOccurred(.success) }
    /// Destructive confirm, over-target warning.
    public static func warn()    { notif.prepare();  notif.notificationOccurred(.warning) }
    /// Picker / segmented control change.
    public static func selection() { select.prepare(); select.selectionChanged() }
    /// Sharp single tick — used by the press-down feedback in TactileButtonStyle.
    public static func tick()    { rigid.prepare();  rigid.impactOccurred(intensity: 0.5) }

    /// Pre-warm a generator before a likely user interaction (e.g. on view appear).
    /// Cuts the first-tap latency to near zero.
    public static func prepare() {
        light.prepare(); medium.prepare(); rigid.prepare(); notif.prepare(); select.prepare()
    }
}
