import SwiftUI
import MudCore

/// The avatars Settings offers, seven to a row, grouped by kind: silhouettes
/// and people, smileys, the silly ones, animals, then nature and desk objects.
///
/// This list is an offering, not the rule. `CommentAvatar.isValid` is the rule,
/// and it takes any single emoji — so anyone who wants one that isn't here can
/// set it directly:
///
///     defaults write org.josephpearson.Mud comment-avatar '🦕'
///
/// `AvatarPicker` shows whatever is stored, so such a value appears on the
/// button with no cell highlighted, and survives until the reader picks from
/// the grid. That is the whole escape hatch: a settings field the reader could
/// type into would have to accept multi-character and non-emoji input and then
/// argue with it, which is what this control exists to avoid.
enum AvatarChoices {
    static let columns = 7

    static let all: [String] = [
        "👤", "🗣️", "💬", "🫥", "🧑", "👩", "👨",
        "🕵️", "🧑‍💻", "🧑‍🎨", "🧑‍🔬", "🙂", "😀", "🤔",
        "🥸", "😎", "🤓", "🧐", "😱", "🥴", "🤯",
        "🤬", "🤡", "👹", "👺", "😈", "👽", "💩",
        "🤖", "👻", "🎃", "🐲", "🐱", "🐶", "🦊",
        "🐼", "🐨", "🦁", "🐯", "🐸", "🦉", "🐝",
        "⭐️", "🏵️", "🍀", "🔥", "🌚", "🖤", "📝"
    ]
}

/// The Settings control for `comment-avatar`: a button showing the current
/// avatar, opening a popover grid of ``AvatarChoices``. Picking a cell writes
/// the preference and closes the popover.
///
/// Nothing here can produce an invalid value, so the preference needs no
/// validation on the way in — every path into it names one of the choices.
struct AvatarPicker: View {
    @Binding var avatar: String

    @State private var isPresented = false

    /// What the button shows and which cell is highlighted: the stored value
    /// put through the same rule the write path uses
    /// (`CommentSubmissionHandler`), so the pane never shows an avatar a
    /// comment wouldn't actually be written with.
    private var resolved: String { CommentAvatar.resolve(avatar) }

    var body: some View {
        Button { isPresented = true } label: {
            HStack(spacing: 5) {
                Text(resolved)
                    .font(.system(size: 15))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .popover(isPresented: $isPresented) { grid }
        .accessibilityLabel("Avatar")
        .accessibilityValue(resolved)
    }

    private var grid: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.fixed(32), spacing: 3),
                count: AvatarChoices.columns
            ),
            spacing: 3
        ) {
            ForEach(AvatarChoices.all, id: \.self) { choice in
                cell(choice)
            }
        }
        .padding(12)
    }

    private func cell(_ choice: String) -> some View {
        Button {
            avatar = choice
            isPresented = false
        } label: {
            Text(choice)
                .font(.system(size: 20))
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(choice == resolved
                              ? Color.accentColor.opacity(0.35)
                              : Color.clear)
                )
                // A plain-styled Button only hit-tests its drawn content, and an
                // emoji glyph doesn't fill its cell.
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}
