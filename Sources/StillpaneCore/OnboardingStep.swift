/// The setup assistant's steps, in the order a first run walks them.
///
/// The ordering rules live here, away from AppKit, so they can be tested:
/// `OnboardingState` owns the live system checks and side effects and asks this
/// type where the flow goes next.
public enum OnboardingStep: Int, CaseIterable, Identifiable, Sendable {
    case welcome
    case accessibility
    case screenRecording
    case claudeCode
    case tryIt
    case done

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .accessibility: return "Accessibility"
        case .screenRecording: return "Screen Recording"
        case .claudeCode: return "Claude Code"
        case .tryIt: return "First capture"
        case .done: return "Done"
        }
    }

    /// The steps the progress indicator draws. `.done` is the end of the flow,
    /// not a stop along it.
    public static var indicatorSteps: [OnboardingStep] {
        allCases.filter { $0 != .done }
    }

    /// Position in `indicatorSteps`; `.done` counts as past the last one so a
    /// finished flow shows every dot filled.
    public var indicatorIndex: Int {
        self == .done ? Self.indicatorSteps.count : rawValue
    }

    /// The next step in raw order, or nil at the end of the flow.
    public var next: OnboardingStep? {
        OnboardingStep(rawValue: rawValue + 1)
    }

    /// True once the flow has moved past `other`, which is what marks a dot
    /// complete.
    public func isPast(_ other: OnboardingStep) -> Bool {
        indicatorIndex > other.indicatorIndex
    }
}
