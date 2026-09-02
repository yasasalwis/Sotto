import Foundation
import LocalAuthentication
import Observation
import os

/// Gate in front of the UI, backed by the device's biometric or passcode policy.
@Observable
final class AppLock {
    enum Status: Equatable {
        case unlocked
        case locked
        case failed(String)
    }

    var status: Status = .unlocked
    private(set) var isPrompting = false

    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    static var biometryLabel: String {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return "Passcode" }
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Passcode"
        }
    }

    func lock() {
        status = .locked
    }

    func unlock() async {
        guard !isPrompting else { return }
        isPrompting = true
        defer { isPrompting = false }
        let context = LAContext()
        context.localizedCancelTitle = "Not now"
        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock your conversations")
            status = success ? .unlocked : .failed("Authentication didn't complete.")
            Log.security.info("App unlock \(success ? "succeeded" : "did not complete", privacy: .public)")
        } catch {
            status = .failed(error.localizedDescription)
            Log.security.notice("App unlock failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
