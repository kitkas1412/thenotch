//
//  ClipboardRow.swift
//  thenotch
//

import AppKit
import SwiftUI

/// One history entry: a thumbnail or icon, a preview, the age and the
/// source app. A button, so VoiceOver reads and presses it.
struct ClipboardRow: View {
    let item: ClipboardItem
    let store: ClipboardStore
    /// 1–9 for the first nine rows (⌘-number), otherwise nil.
    let quickNumber: Int?
    let isSelected: Bool
    let onChoose: () -> Void
    let onHover: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    /// Row height: the search field's, plus the margin around the content.
    static let height: CGFloat = IslandStyle.Size.control + IslandStyle.Spacing.xs

    private var leadingSide: CGFloat { IslandStyle.Size.control - IslandStyle.Spacing.xs }

    var body: some View {
        Button(action: onChoose) {
            HStack(spacing: IslandStyle.Spacing.s) {
                ClipboardLeading(item: item, store: store, side: leadingSide)
                    .frame(width: leadingSide, height: leadingSide)
                    .accessibilityHidden(true)
                preview
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(Self.relative.localizedString(for: item.lastUsedAt, relativeTo: .now))
                    .font(.islandNumeric)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let icon = ClipboardThumbnails.shared.appIcon(bundleID: item.sourceBundleID) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: IslandStyle.Size.smallControl - IslandStyle.Spacing.xs,
                               height: IslandStyle.Size.smallControl - IslandStyle.Spacing.xs)
                        .accessibilityHidden(true)
                }
                // Reserve the hint's width on every row so ages line up.
                Text(quickNumber.map { "⌘\($0)" } ?? "")
                    .font(.islandNumeric)
                    .foregroundStyle(.secondary)
                    .frame(width: IslandStyle.Size.control + IslandStyle.Spacing.xs, alignment: .trailing)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, IslandStyle.Spacing.s)
            .frame(height: Self.height)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                rowFill,
                in: RoundedRectangle(cornerRadius: IslandStyle.Radius.medium, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
            if hovering { onHover() }
        }
        .accessibilityLabel("\(Self.accessibilityLabel(for: item)), \(Self.relative.localizedString(for: item.lastUsedAt, relativeTo: .now))")
        .accessibilityHint(quickNumber.map { "Pastes it. Command \($0) also pastes it. Option-Return pastes as plain text." }
            ?? "Pastes it. Option-Return pastes as plain text.")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: "Delete") { onDelete() }
    }

    private var rowFill: IslandFill {
        .island(isSelected ? .selected : (isHovering ? .hover : .clear))
    }

    @ViewBuilder private var preview: some View {
        switch item.content {
        case .text(let plain, _, _):
            Text(Self.previewText(plain))
                .font(.islandLabel)
                .lineLimit(1)
                .truncationMode(.tail)
        case .image(_, let size, _, _):
            Text("Image \(Int(size.width)) × \(Int(size.height))")
                .font(.islandLabel)
                .lineLimit(1)
        case .files(let paths):
            Text(Self.fileNames(paths))
                .font(.islandLabel)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    // MARK: Text

    /// The first non-blank line, trimmed, capped so a huge copy stays cheap.
    static func previewText(_ plain: String) -> String {
        let head = String(plain.prefix(300))
        let line = head.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        return line ?? "(blank)"
    }

    static func fileNames(_ paths: [String]) -> String {
        let names = paths.map { ($0 as NSString).lastPathComponent }
        guard let first = names.first else { return "No files" }
        return names.count == 1 ? first : "\(first) and \(names.count - 1) more"
    }

    static func accessibilityLabel(for item: ClipboardItem) -> String {
        switch item.content {
        case .text(let plain, _, _):
            let line = previewText(plain).split(separator: "\n").first.map(String.init) ?? ""
            return "Text, \(line)"
        case .image(_, let size, _, _):
            return "Image, \(Int(size.width)) by \(Int(size.height))"
        case .files(let paths):
            return paths.count == 1
                ? "File, \((paths[0] as NSString).lastPathComponent)"
                : "\(paths.count) files"
        }
    }
}

/// The leading visual: an image thumbnail, a file icon, or a text
/// glyph.
private struct ClipboardLeading: View {
    let item: ClipboardItem
    let store: ClipboardStore
    let side: CGFloat

    @Environment(\.displayScale) private var displayScale
    @State private var thumbnail: NSImage?

    var body: some View {
        switch item.content {
        case .text:
            Image(systemName: "text.alignleft")
                .font(.islandSymbol(.control))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .image:
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().scaledToFill()
                } else {
                    Image(systemName: "photo").font(.islandSymbol(.control)).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: IslandStyle.Radius.small, style: .continuous))
            .task(id: item.blobID) {
                thumbnail = await ClipboardThumbnails.shared.thumbnail(
                    for: item, store: store, side: side, scale: displayScale)
            }
        case .files(let paths):
            let path = paths.first ?? ""
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .scaledToFit()
        }
    }
}
