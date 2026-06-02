// Widget extension entry point.
//
// This extension exists solely to host the Live Sessions ActivityKit Live
// Activity (Lock Screen + Dynamic Island). It ships NO Home Screen widgets — the
// bundle contains only the Live Activity configuration. The shared
// `LiveSessionAttributes` (compiled into both this target and the app) is the
// contract between the app, which starts/updates/ends the activity, and the
// widget UI here, which renders it.
//
// `@main` lives here. The whole bundle is gated on iOS 16.2 because that is the
// floor for ActivityKit Live Activities; the extension's deployment target
// matches the app (iOS 17), so this is always satisfied at runtime.

import SwiftUI
import WidgetKit

@main
struct OurFitnessWidgetsBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOS 16.2, *) {
            LiveSessionLiveActivity()
        }
    }
}
