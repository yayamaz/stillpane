/// A snapshot of one element in a window's accessibility tree.
/// Built by the app target's AXTreeReader; consumed by MarkdownRenderer.
public struct AXNode: Equatable, Sendable {
    public var role: String
    public var title: String?
    public var value: String?
    public var url: String?
    public var children: [AXNode]

    public init(
        role: String,
        title: String? = nil,
        value: String? = nil,
        url: String? = nil,
        children: [AXNode] = []
    ) {
        self.role = role
        self.title = title
        self.value = value
        self.url = url
        self.children = children
    }

    /// All human-readable text in this subtree, in document order.
    public var flattenedText: String {
        var parts: [String] = []
        collectText(into: &parts)
        return parts.joined(separator: " ")
    }

    private func collectText(into parts: inout [String]) {
        if let value, !value.isEmpty {
            parts.append(value)
        } else if let title, !title.isEmpty {
            parts.append(title)
        }
        for child in children {
            child.collectText(into: &parts)
        }
    }
}
