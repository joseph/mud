import Foundation

/// Which footnote labels are comments, and which prefix Mud writes.
///
/// A comment's label is one of two equivalent prefixes plus a suffix of word
/// characters or hyphens: `💬-` (what Mud writes) or `comment-` (what it wrote
/// before, and what a hand-author may still write). Both are read forever — the
/// emoji form is shorter, and says the same thing whatever language the
/// document is in.
public enum CommentLabel {
    /// The prefix on every label Mud allocates.
    public static let written = "💬-"

    /// Every prefix that marks a footnote as a comment, ``written`` first.
    public static let prefixes = [written, "comment-"]

    /// True when `label` is a comment label rather than an authorial footnote
    /// label. The prefix is the statement of intent; the suffix is any run of
    /// word characters or hyphens.
    public static func isComment(_ label: String) -> Bool {
        suffix(of: label) != nil
    }

    /// The part of `label` after its comment prefix — `a` in `💬-a` — or nil
    /// when `label` is not a comment label.
    public static func suffix(of label: String) -> Substring? {
        for prefix in prefixes where label.hasPrefix(prefix) {
            let suffix = label.dropFirst(prefix.count)
            guard !suffix.isEmpty, suffix.allSatisfy(isSuffixCharacter)
            else { return nil }
            return suffix
        }
        return nil
    }

    private static func isSuffixCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
            || character == "_" || character == "-"
    }
}
