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

    // MARK: - Crash-recovery restore (restoreClipboardIfNeeded)

    /// A throwaway defaults suite so tests never touch `UserDefaults.standard`.
    private func makePrivateDefaults() -> UserDefaults {
        UserDefaults(suiteName: "autosuggest.tests.\(UUID().uuidString)")!
    }

    func testRestoreClipboardRecoversNewFormatSnapshot() throws {
        // Simulate a crash mid-paste: a plist-encoded snapshot of the user's
        // real clipboard is sitting in defaults, and the pasteboard still holds
        // the suggestion that was pasted in.
        let source = makePrivatePasteboard()
        source.clearContents()
        source.setString("original clipboard", forType: .string)
        let snapshot = PasteboardSnapshot.capture(from: source)

        let defaults = makePrivateDefaults()
        try defaults.set(PropertyListEncoder().encode(snapshot), forKey: AXTextInsertionEngine.clipboardBackupKey)

        let clobbered = makePrivatePasteboard()
        clobbered.clearContents()
        clobbered.setString("the suggestion", forType: .string)

        AXTextInsertionEngine.restoreClipboard(from: defaults, to: clobbered)

        XCTAssertEqual(clobbered.string(forType: .string), "original clipboard")
        XCTAssertNil(defaults.data(forKey: AXTextInsertionEngine.clipboardBackupKey))
    }

    func testRestoreClipboardRecoversLegacyStringBackup() {
        // Backups written by an older app version were plain strings.
        let defaults = makePrivateDefaults()
        defaults.set("legacy original", forKey: AXTextInsertionEngine.clipboardBackupKey)

        let clobbered = makePrivatePasteboard()
        clobbered.clearContents()
        clobbered.setString("the suggestion", forType: .string)

        AXTextInsertionEngine.restoreClipboard(from: defaults, to: clobbered)

        XCTAssertEqual(clobbered.string(forType: .string), "legacy original")
        XCTAssertNil(defaults.string(forKey: AXTextInsertionEngine.clipboardBackupKey))
    }

    func testRestoreClipboardWithNoBackupLeavesClipboardUntouched() {
        // No crash backup pending: a normal launch must not disturb whatever the
        // user currently has on the clipboard.
        let defaults = makePrivateDefaults()

        let pasteboard = makePrivatePasteboard()
        pasteboard.clearContents()
        pasteboard.setString("current clipboard", forType: .string)

        AXTextInsertionEngine.restoreClipboard(from: defaults, to: pasteboard)

        XCTAssertEqual(pasteboard.string(forType: .string), "current clipboard")
    }
}
