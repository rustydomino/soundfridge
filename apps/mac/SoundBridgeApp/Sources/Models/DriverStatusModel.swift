//
// Original prompt:
// Show whether the SoundFridge HAL audio driver is installed.
// Date: 2026-08-10
//
// Build/test with:
//   swift build --package-path apps/mac/SoundBridgeApp
//

import Foundation
import Combine

enum DriverStatus {
    case checking
    case installed
    case notInstalled
}

@MainActor
final class DriverStatusModel: ObservableObject {
    @Published private(set) var status: DriverStatus = .checking

    private let driverPath =
        "/Library/Audio/Plug-Ins/HAL/SoundBridgeDriver.driver"

    /// Check whether the SoundFridge HAL driver bundle is installed.
    func refresh() {
        status = FileManager.default.fileExists(atPath: driverPath)
            ? .installed
            : .notInstalled
    }
}