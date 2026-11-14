//
//  ClipboardHistoryModel.swift
//  thenotch
//

import AppKit
import Carbon.HIToolbox
import Observation

/// The history panel's state: the search text, the selected row and the
/// keyboard map. One per opening, so each opening starts fresh.
@MainActor
@Observable
final class ClipboardHistoryModel {
    var query = ""
    private(set) var selectedID: ClipboardItem.ID?
    /// Bumped by keyboard moves, so the list scrolls (hover doesn't).
    private(set) var scrollRequest = 0

    @ObservationIgnored let tool: ClipboardTool
    @ObservationIgnored var onChoose: (ClipboardItem, Bool) -> Void = { _, _ in }
    @ObservationIgnored var onClose: () -> Void = {}

    /// Where the pointer was when hover last selected a row (or when the
    /// panel opened): a row appearing under a still pointer (opening,
    /// scrolling by keyboard) doesn't take the selection.
    @ObservationIgnored private var lastPointer: CGPoint?
    /// The last search, so the list isn't filtered again on every read.
    @ObservationIgnored private var filtered: (query: String, source: [ClipboardItem], result: [ClipboardItem])?

    /// Text past this many characters isn't searched (a huge copy would
    /// make every keystroke slow).
    static let searchedCharacters = 10_000

    init(tool: ClipboardTool, pointer: CGPoint? = NSEvent.mouseLocation) {
        self.tool = tool
        lastPointer = pointer
        selectedID = tool.store.items.first?.id
    }

    var store: ClipboardStore { tool.store }

    /// Newest first; the search matches text and file names.
    var items: [ClipboardItem] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let all = store.items
        guard !text.isEmpty else { return all }
        // Same array (`==` is quick when the storage is shared).
        if let filtered, filtered.query == text, filtered.source == all { return filtered.result }
        let result = all.filter { Self.matches($0, text) }
        filtered = (text, all, result)
        return result
    }

    var selectedItem: ClipboardItem? {
        let list = items
        return list.first { $0.id == selectedID } ?? list.first
    }

    static func matches(_ item: ClipboardItem, _ text: String) -> Bool {
        switch item.content {
        case .text(let plain, _, _):
            return plain.prefix(searchedCharacters).localizedCaseInsensitiveContains(text)
        case .files(let paths):
            return paths.contains { ($0 as NSString).lastPathComponent.localizedCaseInsensitiveContains(text) }
        case .image:
            return false
        }
    }

    func select(_ id: ClipboardItem.ID) { selectedID = id }

    /// The pointer entered a row: it's selected only if the pointer moved.
    func hover(_ id: ClipboardItem.ID, at pointer: CGPoint) {
        guard pointer != lastPointer else { return }
        lastPointer = pointer
        select(id)
    }

    func choose(_ item: ClipboardItem, asPlainText: Bool = false) {
        onChoose(item, asPlainText)
    }

    func delete(_ item: ClipboardItem) {
        let list = items
        if let index = list.firstIndex(of: item) {
            let next = list.indices.contains(index + 1) ? list[index + 1] : (index > 0 ? list[index - 1] : nil)
            selectedID = next?.id
        }
        store.remove(item.id)
    }

    func move(_ delta: Int) {
        let list = items
        guard !list.isEmpty else { return }
        let current = list.firstIndex { $0.id == selectedItem?.id } ?? 0
        selectedID = list[min(max(current + delta, 0), list.count - 1)].id
        scrollRequest += 1
    }

    /// Returns true if the key was used.
    func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.numericPad, .function])
        let code = Int(event.keyCode)
        switch code {
        case kVK_Escape:
            // First Esc clears the search; the next closes the island.
            if query.isEmpty { onClose() } else { query = "" }
            return true
        case kVK_UpArrow where flags.isEmpty:
            move(-1)
            return true
        case kVK_DownArrow where flags.isEmpty:
            move(1)
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            guard flags.isEmpty || flags == .option, let item = selectedItem else { return true }
            choose(item, asPlainText: flags == .option)
            return true
        case kVK_Delete where flags == .command:
            if let item = selectedItem { delete(item) }
            return true
        default:
            break
        }
        // ⌘1–9 paste the n-th row (by key, whatever the layout or input
        // source types).
        if flags == .command, let digit = Self.quickNumber(keyCode: code) {
            let list = items
            if list.indices.contains(digit - 1) { choose(list[digit - 1]) }
            return true
        }
        return false
    }

    private static let digitKeyCodes = [
        kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
        kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9,
    ]

    /// 1–9 for the digit keys of the top row, else `nil`.
    static func quickNumber(keyCode: Int) -> Int? {
        digitKeyCodes.firstIndex(of: keyCode).map { $0 + 1 }
    }
}
