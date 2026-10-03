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
            .font(.system(size: 13, weight: .semibold).monospacedDigit())
            .foregroundStyle(.primary)
            .accessibilityLabel(store.items.count == 1 ? "1 file on the shelf" : "\(store.items.count) files on the shelf")
    }
}

struct ShelfExpandedView: View {
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
            VStack(spacing: 8) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 26))
                    .accessibilityHidden(true)
                Text("Drag files onto the notch to keep them here")
                    .font(.callout)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                header

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 4) {
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
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
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
        HStack(spacing: 4) {
            if let item = selectedItem {
                Text(item.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("Show in Finder") { onReveal(item) }
                Button("AirDrop…") { onAirDrop([item.url]) }
                Button("Remove") {
                    selection = nil
                    onRemove(item)
                }
            } else {
                Text(store.items.count == 1 ? "1 file" : "\(store.items.count) files")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("AirDrop All…") {
                    onAirDrop(store.items.map(\.url))
                }
                Button("Clear", action: onClear)
            }
        }
        .font(.callout.weight(.medium))
        .buttonStyle(IslandTextButtonStyle())
    }

    /// While files are dragged in: keep them on the shelf, or AirDrop them
    /// right away. A drop elsewhere on the island goes to the shelf.
    private var dropZones: some View {
        HStack(spacing: 10) {
            DropZone(symbol: "tray.and.arrow.down", title: "Keep on Shelf", onDrop: onAdd)
            DropZone(symbol: "dot.radiowaves.left.and.right", title: "AirDrop") { onAirDrop($0.map(\.url)) }
                .frame(width: 140)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }
}

private struct DropZone: View {
    let symbol: String
    let title: String
    var onDrop: ([DroppedFile]) -> Void

    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 22))
                .accessibilityHidden(true)
            Text(title)
                .font(.callout.weight(.medium))
        }
        .foregroundStyle(isTargeted ? .primary : .secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isTargeted ? IslandStyle.hoverFill : .clear)
        )
        // At least 3:1 against black for the zone's edge: 45 % white is
        // #737373, 4.4:1 (30 % was 2.4:1).
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    .white.opacity(isTargeted ? 0.8 : 0.45),
                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                )
        )
        .accessibilityElement(children: .combine)
        .onDrop(of: FileDrop.acceptedTypes, isTargeted: $isTargeted) { providers in
            Task { @MainActor in
                let files = await FileDrop.loadFiles(from: providers)
                if !files.isEmpty {
                    onDrop(files)
                }
            }
            return true
        }
    }
}

private struct ShelfTile: View {
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
        VStack(spacing: 4) {
            ShelfThumbnail(url: item.url)
                .frame(width: 44, height: 44)
            // 11 pt medium: names must read at a glance on black (HIG
            // Live Activities › "Use large, heavier-weight text").
            Text(item.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .frame(width: 68, height: 28, alignment: .top)
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.55) : (isHovering ? IslandStyle.hoverFill : .clear))
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
                    size: CGSize(width: 44, height: 44),
                    scale: displayScale,
                    representationTypes: .thumbnail
                )
                if let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
                    thumbnail = representation.nsImage
                }
            }
    }
}
