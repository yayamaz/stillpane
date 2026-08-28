import Foundation

/// Renders an accessibility tree to readable markdown.
/// Content roles map to markdown structure; controls map to compact
/// bracket notation; unknown containers recurse.
public enum MarkdownRenderer {
    /// Final output ceiling. The tree walk has its own budgets, but many
    /// small strings can still multiply through markdown syntax; past this
    /// point more text costs model context without helping anyone.
    public static let maxOutputBytes = 2 * 1024 * 1024
    private static let truncationNote =
        "[Capture truncated: the window's text exceeded stillpane's size limits.]"

    /// `truncated` marks output whose source tree was already cut short by
    /// the reader's budgets, so the note appears even when the markdown
    /// itself fits.
    public static func render(_ root: AXNode, truncated: Bool = false) -> String {
        var blocks: [String] = []
        renderNode(root, into: &blocks)
        // Carousels and repeated toolbars emit the same control several times
        // in a row; identical adjacent blocks carry no extra information.
        var deduped: [String] = []
        for block in blocks where block != deduped.last {
            deduped.append(block)
        }
        guard !deduped.isEmpty || truncated else { return "" }
        var output = deduped.joined(separator: "\n\n")
        var needsNote = truncated
        if output.utf8.count > maxOutputBytes {
            output = utf8Prefix(output, maxBytes: maxOutputBytes)
            needsNote = true
        }
        if !output.isEmpty { output += "\n" }
        if needsNote {
            output += (output.isEmpty ? "" : "\n") + truncationNote + "\n"
        }
        return output
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

    private static func renderNode(_ node: AXNode, into blocks: inout [String]) {
        switch node.role {
        case "AXHeading":
            let level = headingLevel(from: node.value)
            let text = headingText(node)
            if !text.isEmpty {
                blocks.append(String(repeating: "#", count: level) + " " + text)
            }
        case "AXStaticText", "AXTextArea":
            if let value = node.value, !value.isEmpty {
                blocks.append(value)
            }
        case "AXLink":
            let label = node.flattenedText
            guard !label.isEmpty else { return }
            if let url = node.url, !url.isEmpty {
                blocks.append("[\(label)](\(url))")
            } else {
                blocks.append(label)
            }
        case "AXButton", "AXPopUpButton", "AXCheckBox", "AXRadioButton", "AXMenuItem":
            let label = node.flattenedText
            if !label.isEmpty {
                blocks.append("[\(controlName(node.role)): \(label)]")
            }
        case "AXTextField", "AXSearchField", "AXComboBox":
            let label = node.title ?? ""
            let value = node.value ?? ""
            if !label.isEmpty || !value.isEmpty {
                blocks.append("[Field\(label.isEmpty ? "" : " \(label)"): \(value)]")
            }
        case "AXImage":
            let label = node.flattenedText
            if !label.isEmpty {
                blocks.append("[Image: \(label)]")
            }
        case "AXList":
            let items = node.children
                .map { singleLine($0.flattenedText) }
                .filter { !$0.isEmpty }
            if !items.isEmpty {
                blocks.append(items.map { "- \($0)" }.joined(separator: "\n"))
            }
        case "AXTable", "AXOutline":
            let table = renderTable(node)
            if !table.isEmpty {
                blocks.append(table)
            }
        default:
            if node.children.isEmpty {
                let text = node.flattenedText
                if !text.isEmpty {
                    blocks.append(text)
                }
            } else {
                for child in node.children {
                    renderNode(child, into: &blocks)
                }
            }
        }
    }

    private static func headingLevel(from value: String?) -> Int {
        guard let value, let level = Int(value) else { return 2 }
        return min(max(level, 1), 6)
    }

    private static func headingText(_ node: AXNode) -> String {
        if let title = node.title, !title.isEmpty { return title }
        return node.children.map(\.flattenedText).filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func controlName(_ role: String) -> String {
        switch role {
        case "AXPopUpButton": return "Menu"
        case "AXCheckBox": return "Checkbox"
        case "AXRadioButton": return "Radio"
        case "AXMenuItem": return "MenuItem"
        default: return "Button"
        }
    }

    /// Cellless rows are dropped rather than allowed to become the header,
    /// and short rows are padded so the table stays well-formed markdown.
    /// Rows with extra cells keep them: losing text costs more than a ragged
    /// tail that markdown renderers ignore anyway.
    private static func renderTable(_ node: AXNode) -> String {
        let rows = collectRows(node).filter { !$0.children.isEmpty }
        let cellTexts = rows.map { row in
            row.children.map {
                singleLine($0.flattenedText).replacingOccurrences(of: "|", with: "\\|")
            }
        }
        guard let header = cellTexts.first else { return "" }
        var lines = ["| " + header.joined(separator: " | ") + " |"]
        lines.append("| " + header.map { _ in "---" }.joined(separator: " | ") + " |")
        for row in cellTexts.dropFirst() {
            let padded = row + Array(repeating: "", count: max(0, header.count - row.count))
            lines.append("| " + padded.joined(separator: " | ") + " |")
        }
        return lines.joined(separator: "\n")
    }

    /// Table cells and list items are single-line constructs in markdown, but
    /// accessibility values regularly contain hard line breaks.
    private static func singleLine(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    private static func collectRows(_ node: AXNode) -> [AXNode] {
        var rows: [AXNode] = []
        for child in node.children {
            if child.role == "AXRow" {
                rows.append(child)
            } else {
                rows.append(contentsOf: collectRows(child))
            }
        }
        return rows
    }
}
