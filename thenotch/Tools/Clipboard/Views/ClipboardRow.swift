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

    var body: some View {
        Button(action: onChoose) {
            HStack(spacing: 10) {
                ClipboardLeading(item: item, store: store)
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    preview
                    HStack(spacing: 4) {
                        if let icon = ClipboardThumbnails.shared.appIcon(bundleID: item.sourceBundleID) {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 12, height: 12)
                                .accessibilityHidden(true)
                        }
                        Text(Self.relative.localizedString(for: item.lastUsedAt, relativeTo: .now))
                    }
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color(nsColor: .selectedMenuItemTextColor).opacity(0.8) : .secondary)
                }
                Spacer(minLength: 8)
                if let quickNumber {
                    Text("⌘\(quickNumber)")
                        .font(.caption)
                        .foregroundStyle(isSelected ? Color(nsColor: .selectedMenuItemTextColor).opacity(0.8) : .secondary)
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(isSelected ? Color(nsColor: .selectedMenuItemTextColor) : Color.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .selectedContentBackgroundColor))
                } else if isHovering {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
            if hovering { onHover() }
        }
        .accessibilityLabel(Self.accessibilityLabel(for: item))
        .accessibilityHint("Pastes it. Option-Return pastes as plain text.")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: "Delete") { onDelete() }
    }

    @ViewBuilder private var preview: some View {
        switch item.content {
        case .text(let plain, _, _):
            Text(Self.previewText(plain))
                .font(.body)
                .lineLimit(2)
                .truncationMode(.tail)
        case .image(_, let size, _, _):
            Text("Image \(Int(size.width)) × \(Int(size.height))")
                .font(.body)
                .lineLimit(1)
        case .files(let paths):
            Text(Self.fileNames(paths))
                .font(.body)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }

    // MARK: Text

    /// The first two lines, trimmed, capped so a huge copy stays cheap.
    static func previewText(_ plain: String) -> String {
        let head = String(plain.prefix(300))
        let lines = head.split(separator: "\n", omittingEmptySubsequences: true)
            .prefix(2)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.isEmpty ? "(blank)" : lines.joined(separator: "\n")
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

/// The 32 pt leading visual: an image thumbnail, a file icon, or a text
/// glyph.
private struct ClipboardLeading: View {
    let item: ClipboardItem
    let store: ClipboardStore

    @Environment(\.displayScale) private var displayScale
    @State private var thumbnail: NSImage?

    var body: some View {
        switch item.content {
        case .text:
            Image(systemName: "text.alignleft")
                .font(.title3)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .image:
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().scaledToFill()
                } else {
                    Image(systemName: "photo").font(.title3).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .task(id: item.blobID) {
                thumbnail = await ClipboardThumbnails.shared.thumbnail(
                    for: item, store: store, side: 32, scale: displayScale)
            }
        case .files(let paths):
            let path = paths.first ?? ""
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .scaledToFit()
        }
    }
}
