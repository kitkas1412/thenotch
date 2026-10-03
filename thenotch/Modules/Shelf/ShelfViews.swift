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
    var onAdd: ([URL]) -> Void
    var onAirDrop: ([URL]) -> Void
    var onOpen: (ShelfItem) -> Void
    var onReveal: (ShelfItem) -> Void
    var onRemove: (ShelfItem) -> Void
    var onClear: () -> Void

    @Environment(\.isDraggingFiles) private var isDraggingFiles

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
                                onOpen: onOpen,
                                onReveal: onReveal,
                                onAirDrop: { onAirDrop([$0.url]) },
                                onRemove: onRemove
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
            DropZone(symbol: "dot.radiowaves.left.and.right", title: "AirDrop", onDrop: onAirDrop)
                .frame(width: 140)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }
}

private struct DropZone: View {
    let symbol: String
    let title: String
    var onDrop: ([URL]) -> Void

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
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            Task { @MainActor in
                let urls = await FileDrop.loadFileURLs(from: providers)
                if !urls.isEmpty {
                    onDrop(urls)
                }
            }
            return true
        }
    }
}

private struct ShelfTile: View {
    let item: ShelfItem
    var onOpen: (ShelfItem) -> Void
    var onReveal: (ShelfItem) -> Void
    var onAirDrop: (ShelfItem) -> Void
    var onRemove: (ShelfItem) -> Void

    @State private var isHovering = false
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
                .fill(.white.opacity(isHovering ? 0.12 : 0))
        )
        .overlay(alignment: .topTrailing) {
            if isHovering {
                Button {
                    onRemove(item)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .gray)
                }
                .buttonStyle(.plain)
                .help("Remove from shelf")
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { onOpen(item) }
        // Drag the file itself out (to Finder, Mail, a chat…). Finder
        // copies it; the original stays where it is.
        .onDrag {
            beginDragOut()
            let provider = NSItemProvider(object: item.url as NSURL)
            provider.suggestedName = item.name
            return provider
        }
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
