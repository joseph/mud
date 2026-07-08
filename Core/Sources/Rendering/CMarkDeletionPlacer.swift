/// Places pre-rendered deleted blocks (`RenderedDeletion`) into the cmark
/// Up-mode HTML stream — the Stage 4 port of ``DeletionPlacer``
/// (Doc/Plans/2026-07-single-parser-rendering.md). Pure type substitution:
/// the bookkeeping operates over `RenderedDeletion` values and tag strings,
/// which are parser-agnostic.
///
/// `CMarkDiffContext` keys each deletion to a surviving block in the new
/// AST; `CMarkUpHTMLVisitor` asks for the HTML at the matching point in its
/// walk. The placer owns the bookkeeping that keeps every deletion emitted
/// exactly once as valid HTML:
/// - deletions emitted early (peeked ahead of a list item, hoisted out
///   of a table, or reclaimed into one) are recorded in a consumed set
///   and filtered from later lookups;
/// - non-`<tr>` deletions keyed to a table row are deferred and emitted
///   after `</table>`;
/// - `<tr>` deletions that surface outside a table are wrapped in their
///   own `<table><tbody>`.
struct CMarkDeletionPlacer {
    private let diffContext: CMarkDiffContext
    private var consumedIDs: Set<String> = []
    private var deferred: [RenderedDeletion] = []

    init(diffContext: CMarkDiffContext) {
        self.diffContext = diffContext
    }

    // MARK: - Standard lookup points

    /// Deletions that precede `node`, minus any already emitted early.
    /// `<tr>` deletions are wrapped so the HTML stays valid outside a
    /// table context.
    func precedingHTML(before node: CMarkNode) -> String {
        wrappingTableRows(
            diffContext.precedingDeletions(before: node)
                .filter { !consumedIDs.contains($0.changeID) })
    }

    /// Deletions after the last surviving block (or all deletions when
    /// the new document is empty).
    func trailingHTML() -> String {
        wrappingTableRows(
            diffContext.trailingDeletions()
                .filter { !consumedIDs.contains($0.changeID) })
    }

    // MARK: - Early emission

    /// Deleted `<li>` siblings peeked ahead of a list item's first
    /// child. Emitted before the `<li>` opens so they become valid
    /// siblings rather than nesting inside the item.
    mutating func listItemHTML(before firstChild: CMarkNode) -> String {
        var out = ""
        for del in diffContext.precedingDeletions(before: firstChild)
        where del.tag == "li" {
            out += deletionHTML(del)
            consumedIDs.insert(del.changeID)
        }
        return out
    }

    /// Deletions keyed to a table's head row, hoisted before `<table>`
    /// so they don't become invalid children of the table element.
    /// `<tr>` deletions (from a fully-replaced table) are wrapped in
    /// their own table; other block-level deletions are emitted
    /// directly.
    mutating func hoistedHTML(beforeHead head: CMarkNode) -> String {
        let deletions = diffContext.precedingDeletions(before: head)
        guard !deletions.isEmpty else { return "" }
        var out = ""
        var trDeletions: [RenderedDeletion] = []
        for del in deletions {
            if del.tag == "tr" {
                trDeletions.append(del)
            } else {
                out += deletionHTML(del)
                consumedIDs.insert(del.changeID)
            }
        }
        if !trDeletions.isEmpty {
            out += "<table>\n<tbody>\n"
            for del in trDeletions {
                out += deletionHTML(del)
                consumedIDs.insert(del.changeID)
            }
            out += "</tbody>\n</table>\n"
        }
        return out
    }

    /// Deletions preceding a table-body row: deleted rows emit as
    /// `<tr>` siblings; anything else (e.g. a paragraph deleted after
    /// a table whose deletion is attached to a body row) is deferred
    /// until `deferredHTML()` after `</table>`.
    mutating func rowHTML(before row: CMarkNode) -> String {
        var out = ""
        for del in diffContext.precedingDeletions(before: row) {
            if del.tag == "tr" {
                out += deletionHTML(del)
            } else {
                deferred.append(del)
            }
            consumedIDs.insert(del.changeID)
        }
        return out
    }

    /// Deleted `<tr>` rows that follow the last surviving row,
    /// reclaimed into the table (they would otherwise be emitted
    /// outside it as preceding deletions of the next block, or as
    /// trailing deletions).
    mutating func reclaimedRowHTML(after lastRow: CMarkNode) -> String {
        var out = ""
        for del in diffContext.followingDeletions(after: lastRow)
        where del.tag == "tr" {
            out += deletionHTML(del)
            consumedIDs.insert(del.changeID)
        }
        return out
    }

    /// Emits and clears the deletions deferred from inside a table body.
    mutating func deferredHTML() -> String {
        let out = deferred.map { deletionHTML($0) }.joined()
        deferred.removeAll()
        return out
    }

    // MARK: - Single deletion

    /// A single deletion as a native HTML element with change
    /// attributes.
    func deletionHTML(_ del: RenderedDeletion) -> String {
        let info = diffContext.groupInfo(for: del.changeID)
        var classes = "mud-change-del"
        if let extra = del.extraClasses {
            classes = "\(extra) \(classes)"
        }
        var attrs = " class=\"\(classes)\" data-change-id=\"\(del.changeID)\""
        if let info {
            attrs += " data-group-id=\"\(info.groupID)\""
            attrs += " data-group-type=\"\(info.type.rawValue)\""
            if info.groupPos == .first || info.groupPos == .sole {
                attrs += " data-group-index=\"\(info.groupIndex)\""
            }
        }
        if del.tag == "hr" {
            return "<hr\(attrs) />\n"
        }
        return "<\(del.tag)\(attrs)>\(del.html)</\(del.tag)>\n"
    }

    // MARK: - TR wrapping

    /// Renders a list of deletions, wrapping any `<tr>` runs in
    /// `<table><tbody>…</tbody></table>` so they produce valid HTML
    /// even when emitted outside a table context.
    private func wrappingTableRows(
        _ deletions: [RenderedDeletion]
    ) -> String {
        var out = ""
        var pendingTRs: [RenderedDeletion] = []
        for del in deletions {
            if del.tag == "tr" {
                pendingTRs.append(del)
            } else {
                out += flushTRs(&pendingTRs)
                out += deletionHTML(del)
            }
        }
        out += flushTRs(&pendingTRs)
        return out
    }

    /// Flushes accumulated `<tr>` deletions wrapped in a table.
    private func flushTRs(_ pending: inout [RenderedDeletion]) -> String {
        guard !pending.isEmpty else { return "" }
        var out = "<table>\n<tbody>\n"
        for del in pending {
            out += deletionHTML(del)
        }
        out += "</tbody>\n</table>\n"
        pending.removeAll()
        return out
    }
}
