//
//  ShelfDrag.swift
//  thenotch
//

import AppKit
import os

/// Drags a shelf file out with AppKit, so the file can be *moved*.
///
/// SwiftUI's `onDrag` only offers a copy and never says how the drag
/// ended. Here the destination may move the file (Finder does on the same
/// volume, like Cut + Paste; ⌘ forces a move across volumes, ⌥ a copy) and
/// we learn the operation, so a file dropped anywhere leaves the shelf
/// (`Outcome`).
@MainActor
enum ShelfDrag {
    /// Keeps the current drag's source alive until the drag ends.
    private static var activeSource: Source?

    /// Starts dragging `items` (the shelf's stack drags them all) from the
    /// current mouse-dragged event. Calls `onEnd` with the operation the
    /// destination performed (`[]` if cancelled), which applies to every
    /// file. Returns false if there is no such event.
    @discardableResult
    static func begin(_ items: [ShelfItem], onEnd: @escaping (NSDragOperation) -> Void) -> Bool {
        guard !items.isEmpty,
              let event = NSApp.currentEvent,
              event.type == .leftMouseDragged,
              let view = event.window?.contentView
        else { return false }

        let point = view.convert(event.locationInWindow, from: nil)
        let draggingItems = items.enumerated().map { index, item in
            let draggingItem = NSDraggingItem(pasteboardWriter: item.url as NSURL)
            let icon = NSWorkspace.shared.icon(forFile: item.url.path)
            icon.size = iconSize
            // Fanned out a little under the pointer, like the stack.
            let shift = CGFloat(min(index, 2)) * fanOffset
            draggingItem.setDraggingFrame(
                CGRect(x: point.x - iconSize.width / 2 + shift, y: point.y - iconSize.height / 2 - shift, width: iconSize.width, height: iconSize.height),
                contents: icon
            )
            return draggingItem
        }

        let source = Source { operation in
            activeSource = nil
            onEnd(operation)
        }
        activeSource = source
        view.beginDraggingSession(with: draggingItems, event: event, source: source)
            .animatesToStartingPositionsOnCancelOrFail = true
        return true
    }

    private static let iconSize = CGSize(width: 48, height: 48)
    private static let fanOffset: CGFloat = 4

    /// How a drag out of the shelf ended.
    enum Outcome: Equatable {
        /// Cancelled, or the destination refused it: the file stays.
        case none
        /// Moved elsewhere, or dropped on the Trash: the file left its place.
        case moved
        /// Copied (Finder on another disk) or taken by an app (a browser
        /// upload, a Mail attachment…): the file is still where it was.
        case copied
    }

    static func outcome(of operation: NSDragOperation) -> Outcome {
        if operation.isEmpty { return .none }
        return operation.isDisjoint(with: [.move, .delete]) ? .copied : .moved
    }

    private final class Source: NSObject, NSDraggingSource {
        let onEnd: (NSDragOperation) -> Void

        init(onEnd: @escaping (NSDragOperation) -> Void) {
            self.onEnd = onEnd
        }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            // Dropping back on the island does nothing. Copy stays allowed
            // for apps that can only copy (Mail, chat apps…).
            context == .outsideApplication ? [.move, .copy, .generic, .delete] : []
        }

        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            Log.drop.notice("Drag out ended with operation \(operation.rawValue)")
            MainActor.assumeIsolated {
                onEnd(operation)
            }
        }
    }
}
