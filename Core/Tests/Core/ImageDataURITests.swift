import Testing
@testable import MudCore

@Suite("ImageDataURI")
struct ImageDataURITests {
    // MARK: - isExternal

    @Test func httpIsExternal() {
        #expect(ImageDataURI.isExternal("http://example.com/img.png"))
    }

    @Test func httpsIsExternal() {
        #expect(ImageDataURI.isExternal("https://example.com/img.png"))
    }

    @Test func dataURIIsExternal() {
        #expect(ImageDataURI.isExternal("data:image/png;base64,abc"))
    }

    @Test func mailtoIsExternal() {
        #expect(ImageDataURI.isExternal("mailto:test@example.com"))
    }

    @Test func caseInsensitive() {
        #expect(ImageDataURI.isExternal("HTTP://EXAMPLE.COM"))
        #expect(ImageDataURI.isExternal("Https://Example.com"))
    }

    @Test func relativePathNotExternal() {
        #expect(!ImageDataURI.isExternal("images/photo.png"))
    }

    @Test func absolutePathNotExternal() {
        #expect(!ImageDataURI.isExternal("/usr/local/img.png"))
    }

    @Test func bareFilenameNotExternal() {
        #expect(!ImageDataURI.isExternal("photo.png"))
    }

    // MARK: - MIME types

    @Test func knownMIMETypes() {
        #expect(ImageDataURI.mimeTypes["png"] == "image/png")
        #expect(ImageDataURI.mimeTypes["jpg"] == "image/jpeg")
        #expect(ImageDataURI.mimeTypes["jpeg"] == "image/jpeg")
        #expect(ImageDataURI.mimeTypes["gif"] == "image/gif")
        #expect(ImageDataURI.mimeTypes["svg"] == "image/svg+xml")
        #expect(ImageDataURI.mimeTypes["webp"] == "image/webp")
    }
}
