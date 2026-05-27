// First-launch picker. Both profiles are already seeded; this only sets
// `activeProfileId` for the device and walks the user through the
// HealthKit permission sheet. No editing of vitals — that lives in Settings later.

import SwiftUI

struct OnboardingView: View {
    let profiles: [ProfileDTO]
    let onFinish: (_ chosen: ProfileDTO, _ healthGranted: Bool) -> Void

    @Environment(\.theme) private var theme

    @State private var chosen: ProfileDTO?
    @State private var step: Step = .pickProfile
    @State private var requesting = false

    private enum Step { case pickProfile, connectHealth }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("welcome.")
                    .font(.system(size: 56, weight: .regular))
                    .foregroundStyle(theme.text)

                switch step {
                case .pickProfile:    pickProfileStep
                case .connectHealth:  connectHealthStep
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 36)
        }
        .background(theme.bg.ignoresSafeArea())
    }

    // MARK: - Step 1: pick

    @ViewBuilder
    private var pickProfileStep: some View {
        Text("Who is this device for?")
            .foregroundStyle(theme.dim)
            .padding(.bottom, 12)

        ForEach(profiles) { p in
            PressableCard(action: {
                chosen = p
                step = .connectHealth
            }) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(p.name)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(theme.text)
                    Text(modeBlurb(p.mode))
                        .font(.callout)
                        .foregroundStyle(theme.dim)
                }
            }
            .themed(p.mode)
        }
    }

    // MARK: - Step 2: connect

    @ViewBuilder
    private var connectHealthStep: some View {
        if let p = chosen {
            Text("Connect Apple Health")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(theme.text)

            Text("Steps, weight, resting heart rate, and active energy sync from Apple Health — including Apple Watch. You'll toggle each metric in the system sheet.")
                .font(.callout)
                .foregroundStyle(theme.dim)
                .padding(.bottom, 8)

            Button {
                Task { await connect(grant: true, profile: p) }
            } label: {
                Text(requesting ? "Opening Apple Health…" : "Connect Apple Health")
            }
            .tactile(.primary, fullWidth: true)
            .disabled(requesting)

            Button {
                onFinish(p, false)
            } label: {
                Text("Skip for now")
            }
            .tactile(.ghost)
            .padding(.top, 4)
        }
    }

    private func connect(grant: Bool, profile: ProfileDTO) async {
        requesting = true
        let result = await HealthKitService.shared.requestAuthorization()
        requesting = false
        onFinish(profile, result.isGranted)
    }

    private func modeBlurb(_ m: Mode) -> String {
        switch m {
        case .build: return "Build — gain lean mass, fuel hoops."
        case .reset: return "Reset — drop weight, fix the markers."
        }
    }
}
