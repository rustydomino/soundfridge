//
// Original prompt: Begin SoundFridge first-run onboarding with the smallest
// explicit state model before building the onboarding views.
// Date: 2026-08-14
//
// Used by the SoundFridge GUI.
// Test by building the SoundFridge target in Xcode with Command-B.
//

import Combine
import Foundation

/// The major steps in SoundFridge's first-run experience.
///
/// Keep this intentionally small. The onboarding UI should remain linear
/// rather than growing into a general-purpose navigation framework.
enum OnboardingStep {
    case welcome
    case setup
    case deviceDiscovery
    case complete
}

/// Owns the small amount of state needed for first-run onboarding.
@MainActor
final class OnboardingModel: ObservableObject {
    @Published private(set) var step: OnboardingStep

    private let defaults: UserDefaults
    private let completionKey = "soundfridge.onboarding.completed"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if defaults.bool(forKey: completionKey) {
            step = .complete
        } else {
            step = .welcome
        }
    }

    /// Advance from the welcome screen to component installation.
    func continueFromWelcome() {
        step = .setup
    }

    /// Advance to device discovery after the required components are ready.
    func continueToDeviceDiscovery() {
        step = .deviceDiscovery
    }

    /// Record successful onboarding so future launches go directly to Settings.
    func completeOnboarding() {
        defaults.set(true, forKey: completionKey)
        step = .complete
    }
}
