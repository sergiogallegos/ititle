import ApplicationServices

public enum AccessibilityStatus {
    /// Read-only check. Does not prompt, enumerate windows, or change their frames.
    public static var isTrusted: Bool { AXIsProcessTrusted() }
}
