//
// Original prompt: Add the first visible SoundFridge onboarding screen.
// Date: 2026-08-14
//
// Used by the SoundFridge GUI.
// Test by building the SoundFridge target in Xcode with Command-B.
//

import SwiftUI

struct OnboardingWelcomeView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 52))
                .accessibilityHidden(true)

            VStack(spacing: 10) {
                Text("Welcome to SoundFridge")
                    .font(.title)
                    .fontWeight(.semibold)

                Text(
                    "SoundFridge adds normal macOS volume control to " +
                    "audio devices that don’t provide it themselves."
                )
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                Text(
                    "A small background service keeps volume control " +
                    "working after you close this window."
                )
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 420)

            Spacer()

            HStack {
                Spacer()

                Button("Continue") {
                    onContinue()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(30)
        .frame(width: 520, height: 360)
    }
}
