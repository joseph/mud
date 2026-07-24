import Testing
@testable import MudCore

@Suite("MathRenderer")
struct MathRendererTests {
    @Test func inlineExpressionReturnsMathML() {
        let result = MathRenderer.render("\\pi r^2", displayMode: false)
        #expect(result?.contains("<math") == true)
        #expect(result?.contains("</math>") == true)
        // Inline math is not display-block.
        #expect(result?.contains("display=\"block\"") != true)
    }

    @Test func displayModeMarksBlock() {
        let result = MathRenderer.render(
            "x = \\frac{-b \\pm \\sqrt{b^2-4ac}}{2a}", displayMode: true)
        #expect(result?.contains("<math") == true)
        #expect(result?.contains("display=\"block\"") == true)
    }

    @Test func subscriptSurvives() {
        // The underscore must become a real subscript, not emphasis: this is
        // why the visitor feeds raw source (not cmark's inline-parsed tree).
        let result = MathRenderer.render("a_1 + a_2", displayMode: true)
        #expect(result?.contains("<msub>") == true)
    }

    @Test func invalidTeXRendersErrorNotNil() {
        // Malformed input must not lose content or return nil — Temml's
        // throwOnError:false path emits an in-place error span.
        let result = MathRenderer.render("\\frac{1}{\\notARealCommand", displayMode: true)
        #expect(result != nil)
        #expect(result?.contains("temml-error") == true)
    }

    @Test func emptyExpression() {
        let result = MathRenderer.render("", displayMode: false)
        #expect(result?.contains("<math") == true)
    }
}
