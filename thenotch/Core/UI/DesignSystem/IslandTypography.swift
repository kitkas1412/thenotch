//
//  IslandTypography.swift
//  thenotch
//

import SwiftUI

/// Type scale of the island: SF Pro through the macOS built-in text styles
/// (HIG Typography › "Consider using the built-in text styles"), medium
/// weight or heavier so it reads at a glance on black (HIG Live Activities ›
/// "Use large, heavier-weight text — a medium weight or higher"). Nothing
/// is smaller than 11 pt (macOS minimum: 10 pt). Numbers that change use
/// tabular digits so they don't jitter.
extension Font {
    /// 22 pt semibold, tabular: a value that is the whole message
    /// (battery percentage). macOS Title 1.
    static let islandValue = Font.title.weight(.semibold).monospacedDigit()
    /// 17 pt semibold: the main line, e.g. the track title. macOS Title 2.
    static let islandTitle = Font.title2.weight(.semibold)
    /// 15 pt medium: the line under the title, e.g. the artist. macOS Title 3.
    static let islandSubtitle = Font.title3.weight(.medium)
    /// 13 pt bold: the heading of an empty state. macOS Headline.
    static let islandHeadline = Font.headline
    /// 13 pt semibold, tabular: text in a compact wing. macOS Body,
    /// emphasized.
    static let islandCompact = Font.body.weight(.semibold).monospacedDigit()
    /// 12 pt medium: buttons, labels and messages. macOS Callout.
    static let islandLabel = Font.callout.weight(.medium)
    /// 12 pt medium, tabular: times and counts beside other content.
    static let islandNumeric = Font.callout.weight(.medium).monospacedDigit()
    /// 11 pt medium: file names under thumbnails; the smallest text in the
    /// island. macOS Subheadline.
    static let islandCaption = Font.subheadline.weight(.medium)
}
