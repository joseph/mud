import Markdown

/// Bridge between the diff engine and the rendering visitors.
///
/// A projection of `ChangePlan` for the Up-mode overlay: annotation
/// lookups for AST nodes (used during rendering) and pre-rendered HTML
/// for deleted blocks. Deletion HTML is produced by the `renderDeletion`
/// function injected at construction — the standard one lives in
/// `Rendering/DeletionRenderer.swift`, which also supplies the
/// `DiffContext(old:new:)` convenience initializer.
struct DiffContext {
    private let plan: ChangePlan
    private let annotations: [SourceKey: AnnotationEntry]
    private let precedingDeletionMap: [SourceKey: [RenderedDeletion]]
    private let followingDeletionMap: [SourceKey: [RenderedDeletion]]
    private let _trailingDeletions: [RenderedDeletion]
    private let _codeBlockDiffMap: [SourceKey: CodeBlockDiff]

    /// Projects a change plan into rendering lookups.
    init(
        plan: ChangePlan,
        renderDeletion: (LeafBlock, String, [WordSpan]?) -> RenderedDeletion
    ) {
        var annotations: [SourceKey: AnnotationEntry] = [:]
        var precedingMap: [SourceKey: [RenderedDeletion]] = [:]
        var followingMap: [SourceKey: [RenderedDeletion]] = [:]
        var trailing: [RenderedDeletion] = []
        var codeBlockDiffMap: [SourceKey: CodeBlockDiff] = [:]

        for gap in plan.gaps {
            for slot in gap.insertionSlots {
                switch slot {
                case .block(let change):
                    if let key = sourceKey(for: change.block.markup) {
                        annotations[key] = AnnotationEntry(
                            annotation: .inserted,
                            changeID: change.changeID,
                            wordSpans: plan.wordSpans[change.changeID])
                    }
                case .codeBlockPair(let pair):
                    if let key = sourceKey(for: pair.insertion.block.markup) {
                        codeBlockDiffMap[key] = CodeBlockDiff(lines: pair.lines)
                    }
                }
            }

            guard !gap.deletions.isEmpty else { continue }
            let rendered = gap.deletions.map {
                renderDeletion($0.block, $0.changeID,
                               plan.wordSpans[$0.changeID])
            }

            // Deletions flush to the first keyed block after them — an
            // insertion in the same gap, else the following anchor —
            // or trail after the last surviving block.
            let flushKey = gap.insertionSlots.lazy
                .compactMap { sourceKey(for: $0.insertionBlock.markup) }
                .first
                ?? gap.followingAnchor.flatMap { sourceKey(for: $0.markup) }
            if let flushKey {
                precedingMap[flushKey] = rendered
            } else {
                trailing += rendered
            }

            // Also key the same deletions by the anchor before the gap,
            // so the rendering visitor can reclaim deletions that
            // logically follow a table body.
            if let anchorKey = gap.precedingAnchor
                .flatMap({ sourceKey(for: $0.markup) }) {
                followingMap[anchorKey] = rendered
            }
        }

        self.plan = plan
        self.annotations = annotations
        self.precedingDeletionMap = precedingMap
        self.followingDeletionMap = followingMap
        self._trailingDeletions = trailing
        self._codeBlockDiffMap = codeBlockDiffMap
    }

    // MARK: - Public API

    /// Returns the annotation for a block in the new AST, or `nil` if unchanged.
    func annotation(for node: Markup) -> BlockAnnotation? {
        guard let key = sourceKey(for: node) else { return nil }
        return annotations[key]?.annotation
    }

    /// Returns the change ID for a block in the new AST, or `nil` if unchanged.
    func changeID(for node: Markup) -> String? {
        guard let key = sourceKey(for: node) else { return nil }
        return annotations[key]?.changeID
    }

    /// Returns pre-rendered deleted blocks that should appear before
    /// the given node.
    func precedingDeletions(before node: Markup) -> [RenderedDeletion] {
        guard let key = sourceKey(for: node) else { return [] }
        return precedingDeletionMap[key] ?? []
    }

    /// Returns pre-rendered deleted blocks that follow the given node
    /// (i.e. deletions in the gap after this unchanged block).
    func followingDeletions(after node: Markup) -> [RenderedDeletion] {
        guard let key = sourceKey(for: node) else { return [] }
        return followingDeletionMap[key] ?? []
    }

    /// Returns pre-rendered deleted blocks that appear after the last
    /// surviving block (or all deletions when the new document is empty).
    func trailingDeletions() -> [RenderedDeletion] {
        _trailingDeletions
    }

    /// Returns group info for a change ID, or `nil` if unknown.
    func groupInfo(for changeID: String) -> GroupInfo? {
        plan.groupInfo[changeID]
    }

    /// Returns the change ID of the block paired with the given change ID
    /// (deletion ↔ insertion), or `nil` if the block is unpaired.
    func pairedChangeID(for changeID: String) -> String? {
        plan.pairedChangeID[changeID]
    }

    /// Returns word-level diff spans for a block in the new AST,
    /// or `nil` if the block is unpaired or has divergent structure.
    func wordSpans(for node: Markup) -> [WordSpan]? {
        guard let key = sourceKey(for: node) else { return nil }
        return annotations[key]?.wordSpans
    }

    /// Returns a line-level diff for a code block in the new AST,
    /// or `nil` if the block is not a diffed code block pair.
    func codeBlockDiff(for node: Markup) -> CodeBlockDiff? {
        guard let key = sourceKey(for: node) else { return nil }
        return _codeBlockDiffMap[key]
    }
}

// MARK: - Block annotation

/// The type of change for a block in the new document.
enum BlockAnnotation: Equatable {
    case inserted
}

// MARK: - Rendered deletion

/// A pre-rendered deleted block, ready for injection into the HTML output.
struct RenderedDeletion {
    /// The inner HTML content of the deleted block (no outer tag).
    let html: String
    /// The change ID matching the sidebar entry.
    let changeID: String
    /// Plain-text summary of the deleted content.
    let summary: String
    /// The native HTML tag for this block (e.g. "p", "li", "tr", "pre").
    let tag: String
    /// Word-level diff spans when this deletion is paired with an insertion.
    /// `nil` when unpaired or when inline structure diverges.
    let wordSpans: [WordSpan]?
    /// Extra CSS classes to add to the outer tag (e.g. alert classes).
    let extraClasses: String?

    init(
        html: String, changeID: String, summary: String, tag: String,
        wordSpans: [WordSpan]? = nil, extraClasses: String? = nil
    ) {
        self.html = html
        self.changeID = changeID
        self.summary = summary
        self.tag = tag
        self.wordSpans = wordSpans
        self.extraClasses = extraClasses
    }
}

// MARK: - Source key

/// A hashable key derived from a Markup node's source range,
/// used to look up annotations by AST node.
private struct SourceKey: Hashable {
    let startLine: Int
    let startColumn: Int
    let endLine: Int
    let endColumn: Int
}

private func sourceKey(for node: Markup) -> SourceKey? {
    guard let range = node.range else { return nil }
    return SourceKey(
        startLine: range.lowerBound.line,
        startColumn: range.lowerBound.column,
        endLine: range.upperBound.line,
        endColumn: range.upperBound.column
    )
}

// MARK: - Annotation entry

private struct AnnotationEntry {
    let annotation: BlockAnnotation
    let changeID: String
    let wordSpans: [WordSpan]?

    init(
        annotation: BlockAnnotation, changeID: String,
        wordSpans: [WordSpan]? = nil
    ) {
        self.annotation = annotation
        self.changeID = changeID
        self.wordSpans = wordSpans
    }
}
