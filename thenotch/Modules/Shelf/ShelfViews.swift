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
            .foregroundStyle(.white)
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
                Text("Drag files onto the notch to keep them here")
                    .font(.subheadline)
            }
            .foregroundStyle(.white.opacity(0.6))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    Text(store.items.count == 1 ? "1 file" : "\(store.items.count) files")
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Button("AirDrop All") {
                        onAirDrop(store.items.map(\.url))
                    }
                    Button("Clear", action: onClear)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.8))
                .font(.caption.weight(.medium))

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
            .padding(.bottom, 10)
        }
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
            Text(title)
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(.white.opacity(isTargeted ? 1 : 0.6))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(isTargeted ? 0.12 : 0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    .white.opacity(isTargeted ? 0.7 : 0.3),
                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                )
        )
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
            Text(item.name)
                .font(.system(size: 10))
                .foregroundStyle(.white)
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .frame(width: 64, height: 26, alignment: .top)
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.5) : .white.opacity(isHovering ? 0.12 : 0))
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
            Button("Open") { onOpen(item) }
            Button("Show in Finder") { onReveal(item) }
            Button("AirDrop…") { onAirDrop(item) }
            Divider()
            Button("Remove from Shelf") { onRemove(item) }
        }
        .help(item.name)
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
