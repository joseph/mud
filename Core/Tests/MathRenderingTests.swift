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
