import Foundation
import Testing
@testable import Mud

/// `reduce` is the rule for what the granted-folder list holds after a grant.
/// It is pure and separate from the bookmark handling around it precisely so
/// it can be read here without touching the file system or the sandbox.
@Suite struct AssetAccessStoreTests {

    private func url(_ path: String) -> URL {
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    @Test func addingToAnEmptyListKeepsIt() {
        let result = AssetAccessStore.reduce(
            grants: [], adding: url("/Users/jp/Notes"))

        #expect(result == [url("/Users/jp/Notes")])
    }

    /// Already covered by a wider grant, so nothing changes. A second row
    /// saying the same thing would be noise, and the access is held either way.
    @Test func aFolderInsideAGrantChangesNothing() {
        let grants = [url("/Users/jp")]

        let result = AssetAccessStore.reduce(
            grants: grants, adding: url("/Users/jp/Notes/Images"))

        #expect(result == grants)
    }

    @Test func grantingTheSameFolderTwiceChangesNothing() {
        let grants = [url("/Users/jp/Notes")]

        let result = AssetAccessStore.reduce(
            grants: grants, adding: url("/Users/jp/Notes"))

        #expect(result == grants)
    }

    /// A grant that covers existing ones replaces them, so the list doesn't
    /// keep rows that describe a subset of a permission already held.
    @Test func aParentReplacesTheFoldersItCovers() {
        let grants = [
            url("/Users/jp/Notes"),
            url("/Volumes/Work/Docs"),
            url("/Users/jp/Sketches"),
        ]

        let result = AssetAccessStore.reduce(
            grants: grants, adding: url("/Users/jp"))

        #expect(result == [url("/Volumes/Work/Docs"), url("/Users/jp")])
    }

    @Test func unrelatedFoldersAccumulate() {
        let grants = [url("/Users/jp/Notes")]

        let result = AssetAccessStore.reduce(
            grants: grants, adding: url("/Volumes/Work/Docs"))

        #expect(result == [url("/Users/jp/Notes"), url("/Volumes/Work/Docs")])
    }

    /// Containment is by path component, not by string prefix: `/Users/jp` is
    /// not an ancestor of `/Users/jpsmith`, though one path does begin with
    /// the other. Getting this wrong would silently swallow a real grant.
    @Test func aSharedNamePrefixIsNotContainment() {
        #expect(!AssetAccessStore.covers(url("/Users/jp"), url("/Users/jpsmith")))
        #expect(AssetAccessStore.covers(url("/Users/jp"), url("/Users/jp/Notes")))

        let grants = [url("/Users/jpsmith")]
        let result = AssetAccessStore.reduce(
            grants: grants, adding: url("/Users/jp"))

        #expect(result == [url("/Users/jpsmith"), url("/Users/jp")])
    }

    /// A folder covers itself, which is what makes a repeat grant a no-op.
    @Test func aFolderCoversItself() {
        #expect(AssetAccessStore.covers(url("/Users/jp"), url("/Users/jp")))
    }

    /// Paths are standardized before comparison, so a grant written with `..`
    /// in it still matches the folder it names.
    @Test func pathsAreStandardizedBeforeComparing() {
        #expect(
            AssetAccessStore.covers(
                url("/Users/jp/Notes/../Notes"), url("/Users/jp/Notes/Images")))
    }

    // MARK: What a grant knows about itself

    /// A grant whose bookmark wouldn't resolve at launch — an external disk
    /// that wasn't attached — is kept rather than deleted, so it still has to
    /// name its folder and still has to take part in the reduction above.
    /// Otherwise a grant made below it while it was away would slip in as a
    /// second row, and both would be there when the disk came back.
    @Test func anUnavailableGrantStillNamesItsFolder() {
        let grant = AssetAccessStore.Grant(
            path: "/Volumes/Archive/Notes", url: nil, bookmark: Data([1, 2, 3]))

        #expect(!grant.isAvailable)
        #expect(grant.folder == url("/Volumes/Archive/Notes"))
        let inside = url("/Volumes/Archive/Notes/Images")
        #expect(
            AssetAccessStore.reduce(grants: [grant.folder], adding: inside)
                == [grant.folder])
    }
}
