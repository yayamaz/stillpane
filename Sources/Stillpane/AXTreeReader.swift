import ApplicationServices
import StillpaneCore

/// Walks a window's accessibility tree into AXNode values.
/// Sets AXManualAccessibility on the app first so Electron apps build their
/// tree, polls until that tree's AXWebArea actually appears (it takes about
/// two seconds on a fresh process), and retries once for anything else that
/// comes back near-empty.
enum AXTreeReader {
    private static let maxDepth = 60
    private static let maxNodes = 20_000
    private static let retryDelay: TimeInterval = 0.4
    private static let nearEmptyThreshold = 5
    /// Measured on a freshly launched Notion: the tree appears ~2s after the
    /// opt-in lands. The deadline caps an Electron window that never grows a
    /// web area - a splash screen, say - and the poll interval keeps the
    /// happy path close to the true build time.
    private static let webAreaDeadline: TimeInterval = 3
    private static let webAreaPollInterval: TimeInterval = 0.25
    /// A beachballed or hostile target would otherwise block each of up to
    /// `maxNodes` attribute reads on the default AX timeout, and the capture
    /// would never return at all. FrontmostWindow sets this on the
    /// system-wide AX object before the first call of a capture - a timeout
    /// set on any narrower object bounds only that object.
    static let messagingTimeout: Float = 2
    /// Ceilings for one complete read. The per-call timeout above bounds a
    /// single AX request, but not the walk as a whole: 20,000 nodes at up to
    /// five requests each could otherwise hold a capture busy for minutes,
    /// and strings had no size bound at all. The deadline covers everything,
    /// Electron warm-up and retries included; a call already in flight may
    /// finish, but no further call starts after it passes.
    private static let overallDeadline: TimeInterval = 8
    private static let maxStringBytes = 64 * 1024
    private static let maxTotalStringBytes = 2 * 1024 * 1024

    /// What one read produced, and whether any ceiling cut it short. The
    /// truncation flag stays out of the public AXNode model; it exists so the
    /// rendered markdown can say the capture is incomplete.
    struct ReadResult {
        let root: AXNode
        let truncated: Bool
    }

    /// The ceilings for one read. The deadline spans every walk pass; node
    /// and byte budgets reset per pass, because a re-walk replaces the whole
    /// tree and only the final pass's strings survive.
    private struct ReadBudget {
        let deadline: Date
        var nodesRemaining = maxNodes
        var bytesRemaining = maxTotalStringBytes
        var truncated = false

        /// True once the deadline has passed; records that the read is
        /// incomplete, because a pre-deadline walk never asks.
        mutating func expired() -> Bool {
            guard Date() >= deadline else { return false }
            truncated = true
            return true
        }

        /// Admits a captured string against the per-string and aggregate
        /// caps. Once the aggregate budget is spent, later strings are
        /// dropped entirely rather than squeezed in.
        mutating func admit(_ string: String?) -> String? {
            guard var string else { return nil }
            if string.utf8.count > maxStringBytes {
                string = utf8Prefix(string, maxBytes: maxStringBytes)
                truncated = true
            }
            let bytes = string.utf8.count
            guard bytes <= bytesRemaining else {
                truncated = true
                return nil
            }
            bytesRemaining -= bytes
            return string
        }
    }

    static func read(target: FrontmostTarget) -> ReadResult {
        let deadline = Date().addingTimeInterval(overallDeadline)
        let acceptedOptIn = prepareApplication(pid: target.pid)
        var budget = ReadBudget(deadline: deadline)
        var root = walk(target.axWindow, depth: 0, budget: &budget)
        if acceptedOptIn {
            // Only Electron apps accept the opt-in (Chrome itself rejects it
            // and self-enables), so this branch is exactly the set of apps
            // whose content lives under an AXWebArea that is still being
            // built. Walking the dead shell is ~15 nodes, so polling is
            // cheap right up until the real tree lands.
            let webAreaCutoff = min(deadline, Date().addingTimeInterval(webAreaDeadline))
            while !containsWebArea(root), Date() < webAreaCutoff {
                Thread.sleep(forTimeInterval: webAreaPollInterval)
                budget = ReadBudget(deadline: deadline)
                root = walk(target.axWindow, depth: 0, budget: &budget)
            }
        } else if countNodes(root) <= nearEmptyThreshold, Date() < deadline {
            Thread.sleep(forTimeInterval: retryDelay)
            budget = ReadBudget(deadline: deadline)
            root = walk(target.axWindow, depth: 0, budget: &budget)
        }
        return ReadResult(root: root, truncated: budget.truncated)
    }

    /// The Chromium opt-in the target process needs set before the walk. The
    /// return value is whether the app accepted it - true only for Electron
    /// apps, everything else answers "unsupported attribute".
    private static func prepareApplication(pid: pid_t) -> Bool {
        let axApp = AXUIElementCreateApplication(pid)
        return AXUIElementSetAttributeValue(
            axApp, "AXManualAccessibility" as CFString, kCFBooleanTrue
        ) == .success
    }

    private static func containsWebArea(_ node: AXNode) -> Bool {
        node.role == "AXWebArea" || node.children.contains(where: containsWebArea)
    }

    private static func walk(_ element: AXUIElement, depth: Int, budget: inout ReadBudget) -> AXNode {
        budget.nodesRemaining -= 1
        // The deadline is re-checked before every AX request, so an expired
        // budget stops the walk between calls rather than after this node's
        // full set of reads.
        var node = AXNode(role: "AXUnknown", title: nil, value: nil, url: nil)
        guard !budget.expired() else { return node }
        node.role = stringAttribute(element, kAXRoleAttribute) ?? "AXUnknown"
        guard !budget.expired() else { return node }
        node.title = budget.admit(stringAttribute(element, kAXTitleAttribute))
        guard !budget.expired() else { return node }
        node.value = budget.admit(valueAttribute(element))
        guard !budget.expired() else { return node }
        node.url = budget.admit(urlAttribute(element))

        guard depth < maxDepth, budget.nodesRemaining > 0, !budget.expired() else {
            // A ceiling only truncates when this node actually had children
            // to skip - a leaf landing exactly on a limit is a complete
            // capture. Asking costs one bounded AX call, only at the ceiling,
            // and never once the deadline has already recorded truncation.
            if !budget.truncated, !childElements(element, limit: 1).isEmpty {
                budget.truncated = true
            }
            return node
        }
        // One past the budget, so a level whose children overrun it still
        // trips the truncation guard below without copying the whole array.
        for child in childElements(element, limit: budget.nodesRemaining + 1) {
            guard budget.nodesRemaining > 0, !budget.expired() else {
                budget.truncated = true
                break
            }
            node.children.append(walk(child, depth: depth + 1, budget: &budget))
        }
        return node
    }

    /// The longest prefix of at most `maxBytes` UTF-8 bytes that ends on a
    /// character boundary, so truncation can never produce invalid UTF-8.
    private static func utf8Prefix(_ string: String, maxBytes: Int) -> String {
        var bytes = 0
        var end = string.startIndex
        while end < string.endIndex {
            let next = string.index(after: end)
            let size = string[end..<next].utf8.count
            if bytes + size > maxBytes { break }
            bytes += size
            end = next
        }
        return String(string[..<end])
    }

    private static func copyAttribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var ref: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, name as CFString, &ref)
        return result == .success ? ref : nil
    }

    private static func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
        let value = copyAttribute(element, name) as? String
        return value?.isEmpty == true ? nil : value
    }

    private static func valueAttribute(_ element: AXUIElement) -> String? {
        guard let raw = copyAttribute(element, kAXValueAttribute) else { return nil }
        if let string = raw as? String { return string.isEmpty ? nil : string }
        if let number = raw as? NSNumber { return number.stringValue }
        return nil
    }

    private static func urlAttribute(_ element: AXUIElement) -> String? {
        (copyAttribute(element, kAXURLAttribute) as? URL)?.absoluteString
    }

    /// A ranged copy, so a pathological fanout (an un-virtualized web table,
    /// say) never materializes - or ships over Mach IPC - more children than
    /// the node budget could ever admit. The header allows `maxValues` beyond
    /// the array's length, so only an app that mishandles ranged requests
    /// falls back to the full copy; every other failure means no children.
    private static func childElements(_ element: AXUIElement, limit: Int) -> [AXUIElement] {
        guard limit > 0 else { return [] }
        var ref: CFArray?
        let result = AXUIElementCopyAttributeValues(
            element, kAXChildrenAttribute as CFString, 0, limit, &ref)
        if result == .success, let array = ref as? [AnyObject] {
            return elementsOnly(array)
        }
        guard result == .illegalArgument,
            let raw = copyAttribute(element, kAXChildrenAttribute),
            let array = raw as? [AnyObject]
        else { return [] }
        return elementsOnly(array.count > limit ? Array(array.prefix(limit)) : array)
    }

    private static func elementsOnly(_ array: [AnyObject]) -> [AXUIElement] {
        array.compactMap {
            CFGetTypeID($0) == AXUIElementGetTypeID()
                ? unsafeDowncast($0, to: AXUIElement.self) : nil
        }
    }

    private static func countNodes(_ node: AXNode) -> Int {
        1 + node.children.reduce(0) { $0 + countNodes($1) }
    }
}
