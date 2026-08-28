import Foundation

/// The user's standing choice of what a capture contains.
///
/// Deliberately separate from `OnboardingState.screenRecordingSkipped`, which
/// answers a different question: skipped means the permission was never
/// granted, so nothing should re-prompt for it. This is a preference held by
/// someone who may well have the permission and wants text anyway - for the
/// privacy of leaving no picture on disk, or for the few thousand tokens a
/// screenshot costs on every capture.
enum CaptureSettings {
    private static let textOnlyKey = "captureTextOnly"

    /// Default off: a first capture should show what stillpane does in full.
    static var textOnly: Bool {
        get { UserDefaults.standard.bool(forKey: textOnlyKey) }
        set { UserDefaults.standard.set(newValue, forKey: textOnlyKey) }
    }
}
