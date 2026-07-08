import Testing

@testable import MudCore

/// A smoke test proving the Stage 0 corpus renders today. The comparison it
/// exists for — rendering each document through both the current and the
/// cmark-only pipelines and asserting byte-identical HTML — lands once Stage
/// 1's `CMarkDocument` wrapper does
/// (Doc/Plans/2026-07-single-parser-rendering.md).
@Suite("ParityCorpus renders")
struct ParityCorpusTests {
  @Test(arguments: ParityCorpus.all)
  func rendersNonEmptyHTML(_ document: ParityCorpus.Document) {
    let html = MudCore.renderUpToHTML(document.markdown, options: .init())
    #expect(!html.isEmpty)
  }
}
