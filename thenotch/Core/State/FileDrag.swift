//
//  FileDrag.swift
//  thenotch
//

import UniformTypeIdentifiers

/// Tells a file drag apart from other mouse drags (selecting text, moving
/// a window) using the system drag pasteboard.
///
/// The drag pasteboard keeps the previous drag's contents, so its types
/// alone aren't enough: a new drag session writes to it, which bumps its
/// `changeCount` after the mouse went down.
enum FileDrag {
    static func isFileDrag(changeCount: Int, changeCountAtMouseDown: Int, carriesFiles: Bool) -> Bool {
        changeCount != changeCountAtMouseDown && carriesFiles
    }

    /// Whether a drag with these pasteboard types can be dropped as files:
    /// file URLs, promised files (Photos, Mail attachments…), or content
    /// `FileDrop` saves as a file (an image dragged from a browser). Text
    /// and links don't count.
    static func carriesFiles(_ types: [String], promiseTypes: [String]) -> Bool {
        types.contains { type in
            if promiseTypes.contains(type) { return true }
            guard let utType = UTType(type) else { return false }
            return utType.conforms(to: .fileURL) || FileDrop.contentTypes.contains { utType.conforms(to: $0) }
        }
    }
}
