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

/// The emoji that may lead a message attribution, standing for whoever wrote
/// the message — an avatar. It is optional on disk, and any single emoji.
public enum CommentAvatar {
    /// What Mud writes when the reader has chosen nothing else.
    public static let standard = "👤"

    /// What a rendered attribution shows for a message whose source carries no
    /// avatar: the glyph Mud drew before avatars existed, so a document written
    /// by an older version reads exactly as it did.
    public static let fallback = "💬"

    /// True when `text` is exactly one emoji, which is all an avatar may be.
    public static func isValid(_ text: String) -> Bool {
        text.count == 1 && text.first?.isEmoji == true
    }

    /// `text` when it is a valid avatar, else ``standard``. The preference
    /// holds whatever the reader typed into it, so every write path resolves
    /// through here.
    public static func resolve(_ text: String) -> String {
        isValid(text) ? text : standard
    }
}

extension Character {
    /// True when this character is an emoji: its first scalar carries the Emoji
    /// property, and either presents as emoji by default or is part of a longer
    /// sequence (a variation selector, a keycap, a ZWJ sequence). That second
    /// half is what keeps a bare `#` or `1` — both Emoji-property characters —
    /// from reading as one.
    var isEmoji: Bool {
        guard let first = unicodeScalars.first, first.properties.isEmoji
        else { return false }
        return unicodeScalars.count > 1 || first.properties.isEmojiPresentation
    }
}
