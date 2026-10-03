//
//  ShelfViews.swift
//  thenotch
//

import AppKit
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

struct ShelfCountText: View {
    var store: ShelfStore

    var body: some View {
        Text("\(store.items.count)")
            .font(.islandCompact)
            .foregroundStyle(.primary)
            .accessibilityLabel(store.items.count == 1 ? "1 file on the shelf" : "\(store.items.count) files on the shelf")
    }
}

struct ShelfExpandedView: View {
    /// The header line, one row of tiles, and the bottom margin. Header
    /// text and tile content touch the margins; button capsules and tile
    /// fills, shown on hover or selection, reach into them.
    static let contentHeight = IslandStyle.Size.labelLine + IslandStyle.Spacing.m + ShelfTile.contentHeight + IslandStyle.Spacing.content

    var store: ShelfStore
    var onAdd: ([DroppedFile]) -> Void
    var onAirDrop: ([URL]) -> Void
    var onOpen: (ShelfItem) -> Void
    var onReveal: (ShelfItem) -> Void
    var onRemove: (ShelfItem) -> Void
    /// The file was moved out of its place by dragging it off the shelf.
    var onMovedOut: (ShelfItem) -> Void
    var onClear: () -> Void

    @Environment(\.isDraggingFiles) private var isDraggingFiles
    /// Clicking a file selects it, like in Finder; double-clicking opens it.
    @State private var selection: ShelfItem.ID?

    var body: some View {
        if isDraggingFiles {
            dropZones
        } else if store.items.isEmpty {
            IslandEmptyState(
                title: "Shelf is empty",
                message: "Drag files onto the notch to keep them here.",
                symbol: "tray.and.arrow.down"
            )
        } else {
            VStack(alignment: .leading, spacing: IslandStyle.Spacing.m) {
                header

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: IslandStyle.Spacing.xs) {
                        ForEach(store.items) { item in
                            ShelfTile(
                                item: item,
                                isSelected: selection == item.id,
                                onSelect: { selection = $0.id },
                                onOpen: onOpen,
                                onReveal: onReveal,
                                onAirDrop: { onAirDrop([$0.url]) },
                                onRemove: onRemove,
                                onMovedOut: onMovedOut
                            )
                        }
                    }
                }
                // Tile content touches the margins; the tile's padding,
                // where its hover and selection fill shows, reaches into them.
                .padding(-IslandStyle.Spacing.xs)
            }
            .islandContentMargins()
            // Clicking empty space clears the selection, as in Finder.
            .background {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { selection = nil }
            }
        }
    }

    private var selectedItem: ShelfItem? {
        store.items.first { $0.id == selection }
    }

    /// The tile commands also live here, not only in the context menu
    /// (HIG Context menus › "Always make context menu items available in
    /// the main interface"): they act on the selected file, or on all files.
    private var header: some View {
        HStack(spacing: IslandStyle.Spacing.xs) {
            if let item = selectedItem {
                Text(item.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                Spacer(minLength: IslandStyle.Spacing.s)
                Button("Show in Finder") { onReveal(item) }
                Button("AirDrop…") { onAirDrop([item.url]) }
                Button("Remove") {
                    selection = nil
                    onRemove(item)
                }
            } else {
                Text(store.items.count == 1 ? "1 file" : "\(store.items.count) files")
                    .foregroundStyle(.secondary)
                Spacer(minLength: IslandStyle.Spacing.s)
                Button("AirDrop All…") {
                    onAirDrop(store.items.map(\.url))
                }
                Button("Clear", action: onClear)
            }
        }
        .font(.islandLabel)
        .buttonStyle(.islandText)
        // Borderless buttons: their text, not their hover capsule, lines
        // up with the margins, like the label on the left.
        .padding(.trailing, -IslandStyle.Spacing.s)
        .padding(.vertical, -IslandTextButtonStyle.verticalInset)
    }

    /// While files are dragged in: keep them on the shelf, or AirDrop them
    /// right away. A drop elsewhere on the island goes to the shelf.
    private var dropZones: some View {
        HStack(spacing: IslandStyle.Spacing.m) {
            IslandDropZone(symbol: "tray.and.arrow.down", title: "Keep on Shelf", onDrop: onAdd)
            IslandDropZone(symbol: "dot.radiowaves.left.and.right", title: "AirDrop") { onAirDrop($0.map(\.url)) }
                .frame(width: Self.airDropZoneWidth)
        }
        .islandContentMargins()
    }

    /// Keeping files is the main use, so its zone takes the rest.
    private static let airDropZoneWidth: CGFloat = 140
}

private struct ShelfTile: View {
    /// Thumbnail and two lines of name, without the tile's padding.
    static let contentHeight = IslandStyle.Spacing.xs + IslandStyle.Size.thumbnail + IslandStyle.Size.control

    let item: ShelfItem
    var isSelected: Bool
    var onSelect: (ShelfItem) -> Void
    var onOpen: (ShelfItem) -> Void
    var onReveal: (ShelfItem) -> Void
    var onAirDrop: (ShelfItem) -> Void
    var onRemove: (ShelfItem) -> Void
    var onMovedOut: (ShelfItem) -> Void

    @State private var isHovering = false
    @State private var isDragging = false
    @Environment(\.beginDragOut) private var beginDragOut

    var body: some View {
        VStack(spacing: IslandStyle.Spacing.xs) {
            ShelfThumbnail(url: item.url)
                .frame(width: IslandStyle.Size.thumbnail, height: IslandStyle.Size.thumbnail)
            Text(item.name)
                .font(.islandCaption)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                // Two lines of 11 pt text.
                .frame(width: IslandStyle.Size.tileLabelWidth, height: IslandStyle.Size.control, alignment: .top)
        }
        .padding(IslandStyle.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: IslandStyle.Radius.medium, style: .continuous)
                .fill(isSelected ? AnyShapeStyle(IslandSignal.selection) : AnyShapeStyle(.island(isHovering ? .hover : .clear)))
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2) { onOpen(item) }
        .onTapGesture { onSelect(item) }
        // Drag the file out (to Finder, Mail, a chat…). A Finder drop on
        // the same volume moves it, and it leaves the shelf (Cut + Paste).
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { _ in
                    guard !isDragging else { return }
                    isDragging = ShelfDrag.begin(item) { operation in
                        isDragging = false
                        if ShelfDrag.fileLeft(after: operation) {
                            onMovedOut(item)
                        }
                    }
                    if isDragging {
                        beginDragOut()
                    }
                }
        )
        .contextMenu {
            Button("Open", systemImage: "arrow.up.forward.app") { onOpen(item) }
            Button("Show in Finder", systemImage: "folder") { onReveal(item) }
            Button("AirDrop…", systemImage: "square.and.arrow.up") { onAirDrop(item) }
            Divider()
            Button("Remove from Shelf", systemImage: "minus.circle") { onRemove(item) }
        }
        .help(item.name)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.name)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { onSelect(item) }
        .accessibilityAction(named: "Open") { onOpen(item) }
        .accessibilityAction(named: "Show in Finder") { onReveal(item) }
        .accessibilityAction(named: "Remove from Shelf") { onRemove(item) }
    }
}

/// Quick Look thumbnail (image, PDF, video frame…), or the file's icon
/// while it loads or when there is none.
private struct ShelfThumbnail: View {
    let url: URL
    @State private var thumbnail: NSImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Image(nsImage: thumbnail ?? NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .task(id: url) {
                let request = QLThumbnailGenerator.Request(
                    fileAt: url,
                    size: CGSize(width: IslandStyle.Size.thumbnail, height: IslandStyle.Size.thumbnail),
                    scale: displayScale,
                    representationTypes: .thumbnail
                )
                if let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
                    thumbnail = representation.nsImage
                }
            }
    }
}
