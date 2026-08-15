//
// Original prompt: Add the SoundFridge onboarding explanation shown before
// managing a duplex audio device that may trigger a macOS microphone prompt.
// Date: 2026-08-14
//
// Used by the SoundFridge GUI.
// Test by building the SoundFridge target in Xcode with Command-B.
//

import SwiftUI

struct OnboardingMicrophoneWarningView: View {
    let deviceName: String
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                Text("About Microphone Access")
                    .font(.title)
                    .fontWeight(.semibold)

                Text(
                    "\(deviceName) has both output and input channels. " +
                    "macOS may ask SoundFridge for microphone access when " +
                    "SoundFridge starts audio playback through it."
                )
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                Text(
                    "SoundFridge does not record audio and does not create " +
                    "a microphone device. You can choose “Don’t Allow.” " +
                    "Volume control and playback will continue to work."
                )
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 430)

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