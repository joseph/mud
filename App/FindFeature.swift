import Combine
import SwiftUI
import MudCore
import MudPreferences

// MARK: - Search Types

enum SearchDirection {
    case forward
    case backward
}

enum SearchOrigin {
    case top      // New term: clear selection, scroll to top, find forward
    case refine   // Prefix continuation: collapse selection to start, find forward
    case advance  // Navigation: find from current selection
}

struct MatchInfo: Equatable {
    let current: Int
    let total: Int
}

// MARK: - Search Query

struct SearchQuery: Equatable {
    let id: UUID
    let text: String
    let origin: SearchOrigin
    let direction: SearchDirection
}

// MARK: - Find State

class FindState: ObservableObject {
    @Published var isVisible = false
    @Published var searchText = ""
    @Published private(set) var searchID = UUID()
    @Published private(set) var searchOrigin: SearchOrigin = .top
    @Published private(set) var searchDirection: SearchDirection = .forward
    @Published var matchInfo: MatchInfo?
    private var lastSearchedText = ""
    private var cancellables = Set<AnyCancellable>()

    init() {
        $searchText
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] text in
                self?.autoSearch(text)
            }
            .store(in: &cancellables)
    }

    func show() {
        deferMutation { [self] in
            isVisible = true
        }
    }

    func close() {
        deferMutation { [self] in
            isVisible = false
            searchText = ""
            lastSearchedText = ""
            matchInfo = nil
        }
    }

    func clear() {
        searchText = ""
        lastSearchedText = ""
        matchInfo = nil
    }

    func performFind() {
        findNext()
    }

    func findNext() {
        guard !searchText.isEmpty else { return }
        searchDirection = .forward
        searchOrigin = .advance
        lastSearchedText = searchText
        searchID = UUID()
    }

    func findPrevious() {
        guard !searchText.isEmpty else { return }
        searchDirection = .backward
        searchOrigin = .advance
        lastSearchedText = searchText
        searchID = UUID()
    }

    var currentQuery: SearchQuery? {
        guard isVisible, !searchText.isEmpty else { return nil }
        return SearchQuery(
            id: searchID,
            text: searchText,
            origin: searchOrigin,
            direction: searchDirection
        )
    }

    private func autoSearch(_ text: String) {
        guard isVisible, !text.isEmpty else {
            matchInfo = nil
            lastSearchedText = ""
            return
        }
        if text == lastSearchedText { return }
        searchDirection = .forward
        if lastSearchedText.isEmpty || !text.hasPrefix(lastSearchedText) {
            searchOrigin = .top
        } else {
            searchOrigin = .refine
        }
        lastSearchedText = text
        searchID = UUID()
    }

}

// MARK: - Find Match Counter

private struct FindMatchCounter: View {
    let info: MatchInfo

    var body: some View {
        if info.total > 0, info.total <= 999 {
            Text("\(info.current) of \(info.total)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Floating Bar Tahoe Helpers

extension View {
    @ViewBuilder
    func floatingBarGlass() -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(.regular, in: .capsule)
        } else {
            self
                .background(.ultraThinMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        }
    }

}

// MARK: - Find Bar View

struct FindBar: View {
    @ObservedObject var state: FindState
    var isFocused: FocusState<Bool>.Binding
    @Environment(\.controlActiveState) private var controlActiveState
    @State private var flashDirection: SearchDirection?

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "text.page.badge.magnifyingglass")
                    .padding(.leading, 5)
                    .padding(.trailing, 2)

                TextField("Find…", text: $state.searchText)
                    .textFieldStyle(.plain)
                    .focused(isFocused)
                    .onSubmit { state.performFind() }
                    .onKeyPress(.escape) {
                        state.close()
                        return .handled
                    }

                if let info = state.matchInfo {
                    FindMatchCounter(info: info)
                        .transition(.opacity)
                }

                if !state.searchText.isEmpty {
                    Button("Clear", systemImage: "xmark.circle.fill", action: state.clear)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(6)
            .background(.primary.opacity(1/6), in: ContainerRelativeShape())

            let hasMatches = state.matchInfo.map { $0.total > 0 } ?? false

            Button("Find Previous", systemImage: "chevron.left", action: state.findPrevious)
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .controlSize(.extraLarge)
                .opacity(flashDirection == .backward ? 0.5 : 1)
                .disabled(!hasMatches)

            Button("Find Next", systemImage: "chevron.right", action: state.findNext)
                .labelStyle(.iconOnly)
                .buttonBorderShape(.circle)
                .controlSize(.extraLarge)
                .opacity(hasMatches && flashDirection == .forward ? 0.5 : 1)
                .disabled(!hasMatches)
                .modify { button in
                    if hasMatches && controlActiveState == .key {
                        button.buttonStyle(.borderedProminent)
                    } else {
                        button.buttonStyle(.bordered)
                    }
                }
        }
        .padding(8)
        .frame(maxWidth: 320)
        .containerShape(Capsule())
        .animation(.easeInOut(duration: 0.15), value: state.searchText.isEmpty)
        .onChange(of: state.searchID) {
            guard state.searchOrigin == .advance else { return }
            withAnimation(.easeIn(duration: 0.1)) {
                flashDirection = state.searchDirection
            } completion: {
                withAnimation(.easeOut(duration: 0.2)) {
                    flashDirection = nil
                }
            }
        }
    }
}

// MARK: - Floating Bars Overlay

struct FloatingBarsOverlay: ViewModifier {
    @ObservedObject var findState: FindState
    @ObservedObject var changeTracker: ChangeTracker
    @ObservedObject private var appState = AppState.shared
    @FocusState private var isFindFocused: Bool
    @State private var containerWidth: CGFloat = 0
    var onSelectChange: ([String]) -> Void

    /// Side-by-side bars need roughly this much room (FindBar caps at 320pt
    /// plus the Changes bar); below it, bottom center stacks vertically.
    private static let sideBySideMinWidth: CGFloat = 700

    private var changesBarVisible: Bool {
        appState.changesEnabled
    }

    private enum BarLayout: Equatable {
        case topRightColumn
        case bottomRightColumn
        case bottomCenterColumn   // bottom center, narrow window
        case bottomCenterRow      // bottom center, room for side-by-side

        var overlayAlignment: Alignment {
            switch self {
            case .topRightColumn: .topTrailing
            case .bottomRightColumn: .bottomTrailing
            case .bottomCenterColumn, .bottomCenterRow: .bottom
            }
        }

        var stack: AnyLayout {
            switch self {
            case .topRightColumn, .bottomRightColumn:
                AnyLayout(VStackLayout(alignment: .trailing, spacing: 10))
            case .bottomCenterColumn:
                AnyLayout(VStackLayout(alignment: .center, spacing: 10))
            case .bottomCenterRow:
                AnyLayout(HStackLayout(spacing: 10))
            }
        }
    }

    private var barLayout: BarLayout {
        switch appState.uiFloatingControlsPosition {
        case .topRight: .topRightColumn
        case .bottomRight: .bottomRightColumn
        case .bottomCenter:
            containerWidth >= Self.sideBySideMinWidth
                ? .bottomCenterRow : .bottomCenterColumn
        }
    }

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                containerWidth = width
            }
            .overlay(alignment: barLayout.overlayAlignment) {
                floatingBars
                    .padding(12)
            }
            .animation(.easeOut(duration: 0.15), value: findState.isVisible)
            .animation(.easeOut(duration: 0.15), value: changesBarVisible)
            .animation(.easeOut(duration: 0.15), value: barLayout)
            .onChange(of: findState.isVisible) { _, isVisible in
                if isVisible { isFindFocused = true }
            }
    }

    @ViewBuilder
    private var floatingBars: some View {
        let showFind = findState.isVisible
        let showChanges = changesBarVisible
        if showFind || showChanges {
            floatingBarStack(showFind: showFind, showChanges: showChanges)
        }
    }

    @ViewBuilder
    private func floatingBarStack(showFind: Bool, showChanges: Bool) -> some View {
        barLayout.stack {
            findBarIfVisible(showFind)
            changesBarIfVisible(showChanges)
        }
    }

    @ViewBuilder
    private func findBarIfVisible(_ visible: Bool) -> some View {
        if visible {
            FindBar(state: findState, isFocused: $isFindFocused)
                .floatingBarGlass()
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
        }
    }

    @ViewBuilder
    private func changesBarIfVisible(_ visible: Bool) -> some View {
        if visible {
            ChangesBar(
                changeTracker: changeTracker,
                onSelectChange: onSelectChange
            )
            .floatingBarGlass()
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
        }
    }
}

extension View {
    func floatingBarsOverlay(
        findState: FindState,
        changeTracker: ChangeTracker,
        onSelectChange: @escaping ([String]) -> Void
    ) -> some View {
        modifier(FloatingBarsOverlay(
            findState: findState,
            changeTracker: changeTracker,
            onSelectChange: onSelectChange
        ))
    }
}
