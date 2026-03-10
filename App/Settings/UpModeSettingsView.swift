import MudCore
import SwiftUI

struct UpModeSettingsView: View {
    @ObservedObject private var appState = AppState.shared

    var body: some View {
        Form {
            Section {
                Toggle("Allow Remote Content", isOn: Binding(
                    get: { appState.allowRemoteContent },
                    set: { newValue in
                        appState.allowRemoteContent = newValue
                        appState.saveAllowRemoteContent()
                    }
                ))
                Text("Load remote images and other external resources referenced in Markdown documents.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Extended DocC Alerts", isOn: Binding(
                    get: { appState.showExtendedAlerts },
                    set: { newValue in
                        appState.showExtendedAlerts = newValue
                        appState.saveShowExtendedAlerts()
                    }
                ))
                AlertReferenceTable(showExtendedAlerts: appState.showExtendedAlerts)
                    .padding(.vertical, -10) // XXX-03-2026-JP -- hack to align table to horizontal dividers above and below
                HStack(spacing: 0) {
                    Text("Learn more: ")
                        .foregroundStyle(.secondary)
                    Button("alerts.md") {
                        SettingsWindowController.shared.window?.close()
                        DocumentController.openBundledDocument(
                            "alerts", subdirectory: "Doc/Examples")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.link)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.top, -18) // XXX-03-2026-JP -- hack to align top-of-pane with top-of-sidebar
    }
}

// MARK: - Alert reference table

private extension AlertCategory {
    var nsImage: NSImage? {
        guard let url = iconURL else { return nil }
        return NSImage(contentsOf: url)
    }
}

private struct AlertReferenceTable: View {
    let showExtendedAlerts: Bool
    @Environment(\.colorScheme) private var colorScheme

    // Common categories, in the order they appear in alerts.md.
    private let categories: [AlertCategory] = [
        .note, .status, .tip, .important, .warning, .caution,
    ]

    private typealias Row = (category: AlertCategory, extended: String)

    // Extended aliases, in the order they appear in alerts.md.
    private let rows: [Row] = [
        (category: .note,      extended: "Remark"),
        (category: .note,      extended: "Complexity"),
        (category: .note,      extended: "Author"),
        (category: .note,      extended: "Authors"),
        (category: .note,      extended: "Copyright"),
        (category: .note,      extended: "Date"),
        (category: .note,      extended: "Since"),
        (category: .note,      extended: "Version"),
        (category: .note,      extended: "SeeAlso"),
        (category: .note,      extended: "MutatingVariant"),
        (category: .note,      extended: "NonMutatingVariant"),
        (category: .status,    extended: "ToDo"),
        (category: .tip,       extended: "Experiment"),
        (category: .important, extended: "Attention"),
        (category: .warning,   extended: "Precondition"),
        (category: .warning,   extended: "Postcondition"),
        (category: .warning,   extended: "Requires"),
        (category: .warning,   extended: "Invariant"),
        (category: .caution,   extended: "Bug"),
        (category: .caution,   extended: "Throws"),
        (category: .caution,   extended: "Error"),
    ]

    private var alertProps: [String: String] {
        Color.cssProperties(from: HTMLTemplate.sharedCSS, dark: colorScheme == .dark)
    }

    private func color(for category: AlertCategory) -> Color {
        Color(cssHex: alertProps["alert-\(category.rawValue)-title"])
    }

    var body: some View {
        VStack(spacing: 0) {
            // Sticky header
            HStack(spacing: 0) {
                Text("Common")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                Text("Extended")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
            }
            Divider()
            // Scrollable body — two independent lists side by side
            ScrollView {
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(categories, id: \.rawValue) { category in
                            AlertBadgeView(
                                label: category.title, category: category,
                                isStyled: true, color: color(for: category))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    Divider()
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(rows, id: \.extended) { row in
                            AlertBadgeView(
                                label: row.extended, category: row.category,
                                isStyled: showExtendedAlerts,
                                color: color(for: row.category))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: 144)
        }
        .background(Color(NSColor.textBackgroundColor))
        .animation(.easeInOut(duration: 0.15), value: showExtendedAlerts)
    }
}

private struct AlertBadgeView: View {
    let label: String
    let category: AlertCategory
    let isStyled: Bool
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            if isStyled, let image = category.nsImage {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .foregroundStyle(color)
                    .frame(width: 13, height: 13)
                    .padding(.horizontal, 4)
            }
            if isStyled {
                Text(label)
                    .bold()
                    .foregroundStyle(color)
            } else {
                Text(label)
                    .foregroundStyle(.primary)
            }
        }
    }
}
