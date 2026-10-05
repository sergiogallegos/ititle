// The SDK imports the immutable prompt key as a mutable C global.
@preconcurrency import ApplicationServices

public enum AccessibilityStatus {
    /// Read-only check. Does not prompt, enumerate windows, or change their frames.
    public static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Called only after the user explicitly chooses permission onboarding.
    @MainActor
    public static func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}
