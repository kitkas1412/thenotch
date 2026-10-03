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
/// we learn the operation, so a moved file leaves the shelf too.
@MainActor
enum ShelfDrag {
    /// Keeps the current drag's source alive until the drag ends.
    private static var activeSource: Source?

    /// Starts dragging `item` from the current mouse-dragged event. Calls
    /// `onEnd` with the operation the destination performed (`[]` if
    /// cancelled). Returns false if there is no such event.
    @discardableResult
    static func begin(_ item: ShelfItem, onEnd: @escaping (NSDragOperation) -> Void) -> Bool {
        guard let event = NSApp.currentEvent,
              event.type == .leftMouseDragged,
              let view = event.window?.contentView
        else { return false }

        let draggingItem = NSDraggingItem(pasteboardWriter: item.url as NSURL)
        let icon = NSWorkspace.shared.icon(forFile: item.url.path)
        let size = CGSize(width: 48, height: 48)
        icon.size = size
        let point = view.convert(event.locationInWindow, from: nil)
        draggingItem.setDraggingFrame(
            CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height),
            contents: icon
        )

        let source = Source { operation in
            activeSource = nil
            onEnd(operation)
        }
        activeSource = source
        view.beginDraggingSession(with: [draggingItem], event: event, source: source)
            .animatesToStartingPositionsOnCancelOrFail = true
        return true
    }

    /// Whether the file left its place: moved elsewhere, or dropped on the Trash.
    static func fileLeft(after operation: NSDragOperation) -> Bool {
        !operation.isDisjoint(with: [.move, .delete])
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
