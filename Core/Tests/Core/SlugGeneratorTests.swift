import Testing
@testable import MudCore

@Suite("SlugGenerator")
struct SlugGeneratorTests {
    @Test func plainText() {
        #expect(SlugGenerator.slugify("Hello World") == "hello-world")
    }

    @Test func punctuationStripped() {
        #expect(SlugGenerator.slugify("What's new?") == "whats-new")
    }

    @Test func leadingTrailingSpacesTrimmed() {
        #expect(SlugGenerator.slugify("  hello  ") == "hello")
    }

    @Test func multipleSpacesCollapsed() {
        #expect(SlugGenerator.slugify("a  b") == "a-b")
    }

    @Test func unicodePreserved() {
        #expect(SlugGenerator.slugify("Ñoño") == "ñoño")
    }

    @Test func emptyString() {
        #expect(SlugGenerator.slugify("") == "")
    }

    @Test func alreadySlugged() {
        #expect(SlugGenerator.slugify("hello-world") == "hello-world")
    }

    @Test func hyphensPreserved() {
        #expect(SlugGenerator.slugify("A - B") == "a---b")
    }

    @Test func numbersPreserved() {
        #expect(SlugGenerator.slugify("Section 42") == "section-42")
    }

    // MARK: - Tracker deduplication

    @Test func trackerFirstOccurrenceBare() {
        var tracker = SlugGenerator.Tracker()
        #expect(tracker.slug(for: "Features") == "features")
    }

    @Test func trackerDuplicatesGetSuffix() {
        var tracker = SlugGenerator.Tracker()
        #expect(tracker.slug(for: "Features") == "features")
        #expect(tracker.slug(for: "Features") == "features-1")
        #expect(tracker.slug(for: "Features") == "features-2")
    }

    @Test func trackerDistinctHeadingsUnaffected() {
        var tracker = SlugGenerator.Tracker()
        #expect(tracker.slug(for: "Alpha") == "alpha")
        #expect(tracker.slug(for: "Beta") == "beta")
        #expect(tracker.slug(for: "Alpha") == "alpha-1")
        #expect(tracker.slug(for: "Gamma") == "gamma")
    }
}
