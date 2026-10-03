//
//  FileDrag.swift
//  thenotch
//

/// Tells a file drag apart from other mouse drags (selecting text, moving
/// a window) using the system drag pasteboard.
///
/// The drag pasteboard keeps the previous drag's contents, so its types
/// alone aren't enough: a new drag session writes to it, which bumps its
/// `changeCount` after the mouse went down.
enum FileDrag {
    static func isFileDrag(changeCount: Int, changeCountAtMouseDown: Int, hasFileURLs: Bool) -> Bool {
        changeCount != changeCountAtMouseDown && hasFileURLs
    }
}
