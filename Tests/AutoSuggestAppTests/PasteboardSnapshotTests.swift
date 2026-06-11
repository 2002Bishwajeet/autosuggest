import AppKit
import XCTest
@testable import AutoSuggestApp

@MainActor
final class PasteboardSnapshotTests: XCTestCase {
    /// A throwaway, privately-named pasteboard so tests never touch the user's
    /// real clipboard (`NSPasteboard.general`).
    private func makePrivatePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("autosuggest.tests.\(UUID().uuidString)"))
    }

    private let htmlType = NSPasteboard.PasteboardType("public.html")

    func testRoundTripsPlainString() {
        let pasteboard = makePrivatePasteboard()
        pasteboard.clearContents()
        pasteboard.setString("hello clipboard", forType: .string)

        let snapshot = PasteboardSnapshot.capture(from: pasteboard)

        // Mutate the pasteboard the way insertByClipboardPaste does.
        pasteboard.clearContents()
        pasteboard.setString("suggestion", forType: .string)

        snapshot.restore(to: pasteboard)
        XCTAssertEqual(pasteboard.string(forType: .string), "hello clipboard")
    }

    func testRoundTripsMultiTypeItem() {
        let pasteboard = makePrivatePasteboard()
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString("plain text", forType: .string)
        item.setData(Data("<b>rich</b>".utf8), forType: htmlType)
        pasteboard.writeObjects([item])

        let snapshot = PasteboardSnapshot.capture(from: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString("suggestion", forType: .string)

        snapshot.restore(to: pasteboard)
        XCTAssertEqual(pasteboard.string(forType: .string), "plain text")
        XCTAssertEqual(pasteboard.data(forType: htmlType), Data("<b>rich</b>".utf8))
    }

    func testRoundTripsTwoItems() {
        let pasteboard = makePrivatePasteboard()
        pasteboard.clearContents()
        let first = NSPasteboardItem()
        first.setString("first", forType: .string)
        let second = NSPasteboardItem()
        second.setString("second", forType: .string)
        pasteboard.writeObjects([first, second])

        let snapshot = PasteboardSnapshot.capture(from: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString("suggestion", forType: .string)

        snapshot.restore(to: pasteboard)
        XCTAssertEqual(pasteboard.pasteboardItems?.count, 2)
    }

    func testEmptyPasteboardRestoreClearsStraySuggestion() {
        let pasteboard = makePrivatePasteboard()
        pasteboard.clearContents()

        // Capture an empty pasteboard.
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        XCTAssertTrue(snapshot.items.isEmpty)

        // A stray suggestion is written between capture and restore.
        pasteboard.setString("suggestion", forType: .string)

        // Unconditional restore must clear it — this is the empty-clipboard bug fix.
        snapshot.restore(to: pasteboard)
        XCTAssertNil(pasteboard.string(forType: .string))
        XCTAssertTrue((pasteboard.pasteboardItems ?? []).isEmpty)
    }

    func testPlistRoundTrip() throws {
        let pasteboard = makePrivatePasteboard()
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString("encoded round trip", forType: .string)
        item.setData(Data("<i>html</i>".utf8), forType: htmlType)
        pasteboard.writeObjects([item])

        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        let data = try PropertyListEncoder().encode(snapshot)
        let decoded = try PropertyListDecoder().decode(PasteboardSnapshot.self, from: data)

        pasteboard.clearContents()
        pasteboard.setString("suggestion", forType: .string)

        decoded.restore(to: pasteboard)
        XCTAssertEqual(pasteboard.string(forType: .string), "encoded round trip")
        XCTAssertEqual(pasteboard.data(forType: htmlType), Data("<i>html</i>".utf8))
    }
}
