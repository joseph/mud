import Foundation
import cmark_gfm
import cmark_gfm_extensions

/// The type of a ``CMarkNode``. Core kinds map from `cmark_node_type`
/// constants; extension kinds (tables, strikethrough, task list items) have
/// no exported constants in the public module map, so they are identified by
/// `cmark_node_get_type_string` — exactly as swift-markdown does. Case names
/// follow swift-markdown's types (`.inlineCode`, `.tableHead`, …) so ported
/// consumers read the same.
enum CMarkNodeKind: Hashable, Sendable {
    // Blocks.
    case document
    case blockQuote
    case list
    case listItem
    /// A list item carrying a `[ ]` / `[x]` checkbox. The tasklist extension
    /// reuses `CMARK_NODE_ITEM`, distinguished only by type string.
    case taskListItem
    case codeBlock
    case htmlBlock
    case customBlock
    case paragraph
    case heading
    case thematicBreak
    case footnoteDefinition
    // Inlines.
    case text
    case softBreak
    case lineBreak
    case inlineCode
    case inlineHTML
    case customInline
    case emphasis
    case strong
    case link
    case image
    case footnoteReference
    // Table extension. cmark has no table-body node; `.tableHead` (type
    // string `table_header`) is the header **row**.
    case table
    case tableHead
    case tableRow
    case tableCell
    // Strikethrough extension.
    case strikethrough
    /// An unrecognized type string — future extensions. Walkers descend
    /// through it by default.
    case unknown(String)
}

/// The list flavor of a `.list` node.
enum CMarkListType: Equatable, Sendable {
    case bullet
    case ordered
}

/// One column's alignment in a table, from the delimiter row
/// (`:-` / `:-:` / `-:`).
enum CMarkTableAlignment: Equatable, Sendable {
    case none
    case left
    case center
    case right
}

/// A handle on one node of a ``CMarkDocument``'s tree. The handle retains its
/// owning document, so holding a node anywhere — including across the
/// diff layer's old/new document pairs — keeps the underlying C tree alive.
///
/// **Accessors must remain read-only cmark calls.** The `@unchecked Sendable`
/// conformances on this type and `CMarkDocument` are sound only because the
/// tree is immutable after parsing; a method that mutated a node (or its tree)
/// would break that guarantee and introduce a data race across threads.
struct CMarkNode {
    let raw: UnsafeMutablePointer<cmark_node>
    /// The owning document; retained so `raw` can never dangle.
    let document: CMarkDocument

    // MARK: - Identity

    var kind: CMarkNodeKind {
        // Extension kinds first: a task list item's `cmark_node_type` is
        // plain CMARK_NODE_ITEM, so the type string must win.
        switch typeString {
        case "table": return .table
        case "table_header": return .tableHead
        case "table_row": return .tableRow
        case "table_cell": return .tableCell
        case "strikethrough": return .strikethrough
        case "tasklist": return .taskListItem
        default: break
        }
        switch cmark_node_get_type(raw) {
        case CMARK_NODE_DOCUMENT: return .document
        case CMARK_NODE_BLOCK_QUOTE: return .blockQuote
        case CMARK_NODE_LIST: return .list
        case CMARK_NODE_ITEM: return .listItem
        case CMARK_NODE_CODE_BLOCK: return .codeBlock
        case CMARK_NODE_HTML_BLOCK: return .htmlBlock
        case CMARK_NODE_CUSTOM_BLOCK: return .customBlock
        case CMARK_NODE_PARAGRAPH: return .paragraph
        case CMARK_NODE_HEADING: return .heading
        case CMARK_NODE_THEMATIC_BREAK: return .thematicBreak
        case CMARK_NODE_FOOTNOTE_DEFINITION: return .footnoteDefinition
        case CMARK_NODE_TEXT: return .text
        case CMARK_NODE_SOFTBREAK: return .softBreak
        case CMARK_NODE_LINEBREAK: return .lineBreak
        case CMARK_NODE_CODE: return .inlineCode
        case CMARK_NODE_HTML_INLINE: return .inlineHTML
        case CMARK_NODE_CUSTOM_INLINE: return .customInline
        case CMARK_NODE_EMPH: return .emphasis
        case CMARK_NODE_STRONG: return .strong
        case CMARK_NODE_LINK: return .link
        case CMARK_NODE_IMAGE: return .image
        case CMARK_NODE_FOOTNOTE_REFERENCE: return .footnoteReference
        default: return .unknown(typeString)
        }
    }

    /// cmark's own name for the node type (`"emph"`, `"table_header"`, …),
    /// for diagnostics.
    var typeString: String {
        String(cString: cmark_node_get_type_string(raw))
    }

    // MARK: - Content

    /// The node's string contents: a text/code node's literal (smart
    /// typography already applied), an HTML node's raw HTML, a code block's
    /// body — and, less obviously, a footnote **definition**'s label and a
    /// footnote **reference**'s cmark-assigned number (the conventions
    /// `FootnoteScan` already relies on).
    var literal: String? {
        cmark_node_get_literal(raw).map { String(cString: $0) }
    }

    /// Heading level 1–6; 0 for non-headings.
    var headingLevel: Int { Int(cmark_node_get_heading_level(raw)) }

    /// A fenced code block's info string (`"swift"`); empty for a bare fence,
    /// nil for non-code-block nodes.
    var fenceInfo: String? {
        cmark_node_get_fence_info(raw).map { String(cString: $0) }
    }

    /// A link or image destination; nil elsewhere.
    var url: String? {
        cmark_node_get_url(raw).map { String(cString: $0) }
    }

    /// A link or image title; nil elsewhere.
    var title: String? {
        cmark_node_get_title(raw).map { String(cString: $0) }
    }

    /// The list flavor; nil for non-list nodes.
    var listType: CMarkListType? {
        switch cmark_node_get_list_type(raw) {
        case CMARK_BULLET_LIST: return .bullet
        case CMARK_ORDERED_LIST: return .ordered
        default: return nil
        }
    }

    /// An ordered list's start number; 0 for bullet lists and non-lists.
    var listStart: Int { Int(cmark_node_get_list_start(raw)) }

    /// Whether a list is tight (no blank lines between items). Read straight
    /// off the parser, replacing the old swift-markdown range arithmetic that
    /// inferred list looseness.
    var listIsTight: Bool { cmark_node_get_list_tight(raw) != 0 }

    /// Whether a `.taskListItem`'s checkbox is checked.
    var taskListItemIsChecked: Bool {
        cmark_gfm_extensions_get_tasklist_item_checked(raw)
    }

    /// True for a table's header row (also identifiable as `.tableHead`).
    var tableRowIsHeader: Bool {
        cmark_gfm_extensions_get_table_row_is_header(raw) != 0
    }

    /// A `.table` node's column count; 0 elsewhere.
    var tableColumnCount: Int {
        Int(cmark_gfm_extensions_get_table_columns(raw))
    }

    /// A `.table` node's per-column alignments, from its delimiter row.
    var tableAlignments: [CMarkTableAlignment] {
        let count = tableColumnCount
        guard count > 0,
              let alignments = cmark_gfm_extensions_get_table_alignments(raw)
        else { return [] }
        return (0..<count).map { index in
            switch alignments[index] {
            case UInt8(ascii: "l"): return .left
            case UInt8(ascii: "c"): return .center
            case UInt8(ascii: "r"): return .right
            default: return .none
            }
        }
    }

    // MARK: - Plain text

    /// The node's plain-text content, matching swift-markdown's
    /// `Markup.plainText`: inline code keeps its backtick delimiters, a soft
    /// break becomes a space, a hard break becomes a newline, and other
    /// inline containers (emphasis, strong, links, images, strikethrough)
    /// join their children's plain text. Distinct from
    /// `WordDiff.inlineText(of:)`, which strips the backticks to match the
    /// rendering visitor's character count.
    var plainText: String {
        var result = ""
        for child in children {
            switch child.kind {
            case .text:
                result += child.literal ?? ""
            case .inlineCode:
                result += "`\(child.literal ?? "")`"
            case .softBreak:
                result += " "
            case .lineBreak:
                result += "\n"
            case .inlineHTML, .customInline:
                result += child.literal ?? ""
            default:
                result += child.plainText
            }
        }
        return result
    }

    // MARK: - Structure

    var parent: CMarkNode? { wrap(cmark_node_parent(raw)) }
    var firstChild: CMarkNode? { wrap(cmark_node_first_child(raw)) }
    var nextSibling: CMarkNode? { wrap(cmark_node_next(raw)) }
    var previousSibling: CMarkNode? { wrap(cmark_node_previous(raw)) }

    /// The footnote definition a `.footnoteReference` resolves to (cmark
    /// keeps the label on the definition, not the reference); nil elsewhere.
    var parentFootnoteDefinition: CMarkNode? {
        wrap(cmark_node_parent_footnote_def(raw))
    }

    /// The node's children in order, for `for`-loops and the walker's
    /// default descent.
    var children: CMarkChildren { CMarkChildren(node: firstChild) }

    private func wrap(
        _ pointer: UnsafeMutablePointer<cmark_node>?
    ) -> CMarkNode? {
        pointer.map { CMarkNode(raw: $0, document: document) }
    }

    // MARK: - Positions

    /// Raw cmark sourcepos fields: 1-based, **inclusive** end, UTF-8 byte
    /// columns; 0 when untracked. Prefer ``range`` (swift-markdown
    /// conventions) unless porting code that read cmark directly.
    var startLine: Int { Int(cmark_node_get_start_line(raw)) }
    var startColumn: Int { Int(cmark_node_get_start_column(raw)) }
    var endLine: Int { Int(cmark_node_get_end_line(raw)) }
    var endColumn: Int { Int(cmark_node_get_end_column(raw)) }

    /// The opening backtick-run length of an inline code span; 0 elsewhere.
    var backtickCount: Int { Int(cmark_node_get_backtick_count(raw)) }

    /// See ``CMarkDocument/range(of:)``.
    var range: Range<CMarkSourceLocation>? { document.range(of: self) }

    /// See ``CMarkDocument/byteRange(of:)``.
    var byteRange: Range<Int>? { document.byteRange(of: self) }

    /// See ``CMarkDocument/verifiedRange(of:)``.
    var verifiedRange: Range<Int>? { document.verifiedRange(of: self) }
}

/// Node identity is tree-node identity: two handles are equal when they point
/// at the same node of the same tree.
extension CMarkNode: Equatable {
    static func == (lhs: CMarkNode, rhs: CMarkNode) -> Bool {
        lhs.raw == rhs.raw
    }
}

extension CMarkNode: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(raw)
    }
}

// @unchecked because of the raw pointer; safe for the same reason as
// `CMarkDocument` — the tree is immutable after parsing and the retained
// document keeps it alive.
extension CMarkNode: @unchecked Sendable {}

/// Sibling-order iteration over a node's children.
struct CMarkChildren: Sequence, IteratorProtocol {
    var node: CMarkNode?

    mutating func next() -> CMarkNode? {
        defer { node = node?.nextSibling }
        return node
    }
}
