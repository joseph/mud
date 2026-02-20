import Combine
import SwiftUI

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
            matchInfo = nil
        } else {
            searchOrigin = .refine
        }
        lastSearchedText = text
        searchID = UUID()
    }

}

// MARK: - Find Bar View

struct FindBar: View {
    @ObservedObject var state: FindState
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 14))

            TextField("Find", text: $state.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .frame(width: 180)
                .focused(isFocused)
                .onSubmit {
                    state.performFind()
                }
                .onKeyPress(.escape) {
                    state.close()
                    return .handled
                }

            ZStack(alignment: .trailing) {
                // Reserve stable width for up to 3-digit counts.
                HStack(spacing: 8) {
                    Text("0 of 000")
                        .font(.system(size: 12))
                        .monospacedDigit()
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .hidden()

                if let info = state.matchInfo {
                    if info.total > 0 && info.total <= 999 {
                        HStack(spacing: 8) {
                            Text("\(info.current) of \(info.total)")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()

                            Button(action: { state.findPrevious() }) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .buttonStyle(.borderless)

                            Button(action: { state.findNext() }) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .buttonStyle(.borderless)
                        }
                    } else if info.total > 999 {
                        HStack(spacing: 8) {
                            Button(action: { state.findPrevious() }) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .buttonStyle(.borderless)

                            Button(action: { state.findNext() }) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .buttonStyle(.borderless)
                        }
                    } else {
                        Text("No matches")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Button(action: { state.close() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .padding(.leading, 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
    }
}

// MARK: - Find Overlay Modifier

struct FindOverlay: ViewModifier {
    @ObservedObject var state: FindState
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                if state.isVisible {
                    FindBar(state: state, isFocused: $isFocused)
                        .padding(12)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .animation(.easeOut(duration: 0.15), value: state.isVisible)
            .onChange(of: state.isVisible) { _, isVisible in
                if isVisible { isFocused = true }
            }
    }
}

extension View {
    func findOverlay(state: FindState) -> some View {
        modifier(FindOverlay(state: state))
    }
}
