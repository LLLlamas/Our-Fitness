// Train tab container: the live-session surface on top, quick-log below.
//
// One List, two sections — each child supplies its OWN Section so swipe
// actions land on real List rows (they don't work inside a ScrollView), and so
// the two surfaces stay independently readable at 40mm without nesting Lists.
//
// Pure container: no state, no logic. WatchLiveSessionView owns the session
// picker/runner, WatchQuickLogView owns the movement rows.

import SwiftUI

struct WatchTrainView: View {
    var body: some View {
        List {
            WatchLiveSessionView()
            WatchQuickLogView()
        }
        .navigationTitle("Train")
    }
}
