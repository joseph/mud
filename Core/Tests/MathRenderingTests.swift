import Foundation
import Testing

@testable import MudCore

/// Math detection in the Up visitor and the conditional stylesheet. The three
/// GFM forms — a ```` ```math ```` block, a `$$…$$` paragraph, and inline
/// `` $`…`$ `` — each render to a `<math>` element; a bare `$…$` does not.
/// `MathRenderer`'s TeX→MathML conversion itself is covered by
/// `MathRendererTests`.
@Suite("Math rendering")
struct MathRenderingTests {

    // MARK: - The three forms

    @Test func fencedMathBlockRendersMathML() {
        let body = UpHTMLVisitor.renderBody(
            "```math\n\\pi r^2\n```", options: .init())
        #expect(body.contains("mud-math-block"))
        #expect(body.contains("<math"))
        #expect(body.contains("display=\"block\""))
        // Not a code block.
        #expect(!body.contains("language-math"))
    }

    @Test func displayMathParagraphRendersMathML() {
        let body = UpHTMLVisitor.renderBody(
            "$$ x = y^2 $$", options: .init())
        #expect(body.contains("mud-math-block"))
        #expect(body.contains("<math"))
        #expect(body.contains("display=\"block\""))
    }

    @Test func inlineMathRendersMathML() {
        let body = UpHTMLVisitor.renderBody(
            "The area is $`\\pi r^2`$ exactly.", options: .init())
        #expect(body.contains("<math"))
        // Inline, not display.
        #expect(!body.contains("display=\"block\""))
        // The `$` delimiters are consumed, not left as literal text.
        #expect(!body.contains("$`"))
        #expect(!body.contains("`$"))
        // The surrounding prose survives.
        #expect(body.contains("The area is"))
        #expect(body.contains("exactly."))
    }

    // MARK: - Source recovery

    @Test func displayMathSubscriptSurvivesEmphasisMangling() {
        // `$$a_1 + a_2$$`: cmark inline-parses the interior and would turn the
        // underscores into emphasis. Rendering from the raw source instead
        // yields real subscripts, and no stray <em>.
        let body = UpHTMLVisitor.renderBody("$$ a_1 + a_2 $$", options: .init())
        #expect(body.contains("<msub>"))
        #expect(!body.contains("<em>"))
    }

    @Test func blockquotedDisplayMathStripsQuoteMarkers() {
        // A multi-line $$ paragraph inside a blockquote spans the `> `
        // continuation markers in its byte range; they must not reach Temml
        // as TeX relation operators.
        let body = UpHTMLVisitor.renderBody(
            "> $$\n> a_1 + b_1\n> $$", options: .init())
        #expect(body.contains("<math"))
        #expect(body.contains("<msub>"))
        #expect(!body.contains("temml-error"))
        #expect(!body.contains("&gt;"))
    }

    // MARK: - What is not math

    @Test func bareDollarsAreNotMath() {
        // Prices in prose keep their dollar signs; nothing renders as math.
        let body = UpHTMLVisitor.renderBody(
            "A coffee is $3 and a refill is $2.", options: .init())
        #expect(!body.contains("<math"))
        #expect(body.contains("$3"))
        #expect(body.contains("$2"))
    }

    @Test func bareInlineDollarPairIsNotMath() {
        // A single-dollar pair is deliberately not recognized (GitHub requires
        // the backtick form for inline math).
        let body = UpHTMLVisitor.renderBody("Here $x + y$ stays literal.",
                                            options: .init())
        #expect(!body.contains("<math"))
        #expect(body.contains("$x + y$"))
    }

    @Test func escapedDollarsAreNotMathDelimiters() {
        // `\$` is GitHub's opt-out: the resolved literal still ends with a
        // plain `$`, so the raw-source byte check must decline the span.
        let body = UpHTMLVisitor.renderBody(
            "pay \\$`amount`\\$ upfront", options: .init())
        #expect(!body.contains("<math"))
        #expect(body.contains("<code>amount</code>"))
        // Both dollars survive as literal text.
        #expect(body.contains("pay $"))
        #expect(body.contains("$ upfront"))
    }

    // MARK: - Math in context

    @Test func mathInFootnoteBodyRenders() {
        // A footnote body is rendered (through the same visitor) into the bottom
        // footnotes section, not the main body walk — so assert on the full
        // document, which appends that section.
        let markdown = """
            The series diverges.[^1]

            [^1]: That is, $`\\sum_{n=1}^{\\infty} \\frac{1}{n}`$ grows.
            """
        let doc = MudCore.renderUpModeDocument(markdown)
        #expect(doc.contains("<math"))
    }

    // MARK: - Change tracking

    @Test func editedHeadingKeepsInlineMath() {
        // Word spans never activate on a math-bearing block (any block kind,
        // any nesting depth), so an edited heading renders MathML instead of
        // degrading to a literal code span with visible `$` delimiters.
        var options = RenderOptions()
        options.waypoint = ParsedMarkdown("## Energy $`E=mc^2`$ was")
        let body = UpHTMLVisitor.renderBody(
            "## Energy $`E=mc^2`$ is", options: options)
        #expect(body.contains("<math"))
        #expect(!body.contains("$`"))
    }

    @Test func editedParagraphKeepsEmphasisNestedMath() {
        // Math nested inside emphasis is still math when the paragraph is
        // change-annotated: the word-span choke point sees any depth.
        var options = RenderOptions()
        options.waypoint = ParsedMarkdown("*see $`x_1`$* maybe")
        let body = UpHTMLVisitor.renderBody(
            "*see $`x_1`$* certainly", options: options)
        #expect(body.contains("<math"))
        #expect(!body.contains("$`"))
    }

    @Test func editedMathBlockAnnotatesWholeBlock() {
        // An edited ```math block never code-block-pairs (no per-line code
        // display to project a line diff onto), so the new block carries the
        // whole-block insertion annotation the sidebar's change IDs point at.
        var options = RenderOptions()
        options.waypoint = ParsedMarkdown("```math\na+b\n```")
        let body = UpHTMLVisitor.renderBody(
            "```math\na+c\n```", options: options)
        #expect(body.contains("mud-math-block mud-change-ins"))
        #expect(body.contains("data-change-id"))
        #expect(body.contains("<math"))
    }

    @Test func deletedDisplayMathRendersMathML() {
        // The deletion overlay renders deleted math as MathML, not as raw
        // TeX with cmark's emphasis mangling.
        var options = RenderOptions()
        options.waypoint = ParsedMarkdown(
            "Intro.\n\n$$ a_1 + b_1 $$\n\nOutro.")
        let body = UpHTMLVisitor.renderBody(
            "Intro.\n\nOutro.", options: options)
        #expect(body.contains("mud-math-block"))
        #expect(body.contains("<math"))
        #expect(!body.contains("$$"))
    }

    // MARK: - Conditional stylesheet

    @Test func mathCSSPresentOnlyWhenDocumentHasMath() {
        let withMath = MudCore.renderUpModeDocument("$$ x = y $$")
        #expect(withMath.contains("mud-math-block"))
        // A marker unique to mud-math.css.
        #expect(withMath.contains("tml-display"))

        let withoutMath = MudCore.renderUpModeDocument("Just prose, no math.")
        #expect(!withoutMath.contains("tml-display"))
    }

    @Test func invalidMathStillTriggersStylesheet() {
        // An invalid expression renders a `temml-error` span with no `<math>`;
        // the stylesheet must still be included so the error is styled.
        let doc = MudCore.renderUpModeDocument("```math\n\\frac{1}{\\bad\n```")
        #expect(doc.contains("temml-error"))
        #expect(doc.contains("tml-display"))
    }

    // MARK: - Down mode

    @Test func downModeLeavesMathAsRawSource() {
        // Down mode shows raw source; a ```math block is just a fenced block
        // there, never converted to MathML.
        let html = MudCore.renderDownToHTML("```math\n\\pi r^2\n```")
        #expect(!html.contains("<math"))
    }
}
