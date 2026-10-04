//
//  ShelfViews.swift
//  thenotch
//

import AppKit
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

/// Which layout the open shelf shows. It opens on the stack, a small
/// square like Dropover's; "Show All" widens it to the list, until the
/// island closes.
@MainActor
@Observable
final class ShelfPresentation {
    var showsAll = false
}

/// What the shelf's views can do, provided by `ShelfModule`.
struct ShelfActions {
    var airDrop: ([URL]) -> Void
    var open: (ShelfItem) -> Void
    var reveal: ([ShelfItem]) -> Void
    var remove: (ShelfItem) -> Void
    /// Files were dropped somewhere by dragging them off the shelf.
    var draggedOut: ([ShelfItem], ShelfDrag.Outcome) -> Void
    var clear: () -> Void
}

/// The open shelf: its stack, or all files in a row.
struct ShelfView: View {
    var store: ShelfStore
    var presentation: ShelfPresentation
    var actions: ShelfActions

    var body: some View {
        if presentation.showsAll {
            ShelfListView(store: store, actions: actions)
                .transition(.opacity)
        } else {
            ShelfStackView(store: store, presentation: presentation, actions: actions)
                .transition(.opacity)
        }
    }
}

/// The shelf as a small square: the newest files stacked and fanned out,
/// like Dropover's shelf. Dragging the stack drags every file; "Show All"
/// opens the list. It has no hover or selection fill: it is one object,
/// not a list of choices.
struct ShelfStackView: View {
    /// Width of the island while it shows the stack: about as wide as it
    /// is tall. It leaves a band beside the notch narrower than the tabs,
    /// so they take a row under the notch (`IslandState.tabsBesideNotch`).
    static let islandWidth: CGFloat = 256
    /// Clear and More, the stack, "Show All", and the bottom margin.
    static let contentHeight = IslandStyle.Size.smallControl + IslandStyle.Spacing.s + stackSide
        + IslandStyle.Spacing.m + IslandStyle.Size.control + IslandStyle.Spacing.content
    /// The top file and room for the ones fanned out behind it.
    static let stackSide = IslandStyle.Size.stackThumbnail + IslandStyle.Spacing.l
    /// Files drawn in the stack; more only add to the count.
    static let shownFiles = 3
    static let airDropZone = "AirDrop"

    var store: ShelfStore
    var presentation: ShelfPresentation
    var actions: ShelfActions

    @Environment(\.isDraggingFiles) private var isDraggingFiles
    @Environment(\.beginDragOut) private var beginDragOut
    @State private var isDragging = false

    var body: some View {
        if store.items.isEmpty && !isDraggingFiles {
            IslandEmptyState(
                title: "Shelf is empty",
                message: "Drag files onto the notch to keep them here.",
                symbol: "tray.and.arrow.down"
            )
        } else {
            VStack(spacing: IslandStyle.Spacing.m) {
                if isDraggingFiles {
                    // While files are dragged in, the whole island takes
                    // them (its border shows it); only a hint is left here.
                    ShelfDropHint()
                } else {
                    VStack(spacing: IslandStyle.Spacing.s) {
                        // Their own row above the files, clear of them.
                        HStack {
                            clearButton
                            Spacer(minLength: 0)
                            moreButton
                        }
                        .frame(height: IslandStyle.Size.smallControl)
                        stack
                    }
                }
                buttons
            }
            .frame(height: Self.contentHeight - IslandStyle.Spacing.content, alignment: .top)
            .islandContentMargins()
        }
    }

    /// Not shown: the stack speaks for itself (the count is beside the
    /// notch). Used for the tooltip and VoiceOver.
    private var caption: String {
        let items = store.items
        return items.count == 1 ? items[0].name : "\(items.count) files"
    }

    /// The newest file on top, the next two fanned out behind it.
    private var stack: some View {
        let shown = Array(store.items.prefix(Self.shownFiles).enumerated())
        return ZStack {
            ForEach(shown.reversed(), id: \.element.id) { index, item in
                ShelfThumbnail(url: item.url, side: IslandStyle.Size.stackThumbnail)
                    .frame(width: IslandStyle.Size.stackThumbnail, height: IslandStyle.Size.stackThumbnail)
                    .rotationEffect(Self.fan[index].angle)
                    .offset(x: Self.fan[index].x)
            }
        }
        .frame(width: Self.stackSide, height: Self.stackSide)
        .contentShape(Rectangle())
        // One file opens; several show them all.
        .onTapGesture(count: 2) {
            if store.items.count == 1 {
                actions.open(store.items[0])
            } else {
                showAll()
            }
        }
        // Dragging the stack drags every file on the shelf; dropped
        // anywhere, they leave it (`ShelfDrag`).
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { _ in
                    guard !isDragging else { return }
                    let items = store.items
                    isDragging = ShelfDrag.begin(items) { operation in
                        isDragging = false
                        let outcome = ShelfDrag.outcome(of: operation)
                        if outcome != .none {
                            actions.draggedOut(items, outcome)
                        }
                    }
                    if isDragging {
                        beginDragOut()
                    }
                }
        )
        .contextMenu {
            Button("Show All", systemImage: "square.grid.2x2") { showAll() }
            Button("Show in Finder", systemImage: "folder") { actions.reveal(store.items) }
            Button("AirDrop…", systemImage: "square.and.arrow.up") { actions.airDrop(store.items.map(\.url)) }
            Divider()
            Button("Clear Shelf", systemImage: "minus.circle") { actions.clear() }
        }
        .help(caption)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(store.items.count == 1 ? caption : "\(caption) on the shelf")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { showAll() }
        .accessibilityAction(named: "Show in Finder") { actions.reveal(store.items) }
        .accessibilityAction(named: "AirDrop") { actions.airDrop(store.items.map(\.url)) }
        .accessibilityAction(named: "Clear Shelf") { actions.clear() }
    }

    /// Rotation and horizontal shift of the files, top first.
    private static let fan: [(angle: Angle, x: CGFloat)] = [
        (.zero, 0),
        (.degrees(-8), -IslandStyle.Spacing.s),
        (.degrees(8), IslandStyle.Spacing.s),
    ]

    /// Top left: empties the shelf (the files themselves stay where they
    /// are).
    private var clearButton: some View {
        Button(action: actions.clear) {
            Label("Clear Shelf", systemImage: "xmark")
                .font(.islandSymbol(.small, weight: .bold))
        }
        .buttonStyle(.islandIcon(isFilled: true, size: IslandStyle.Size.smallControl))
        .help("Clear Shelf")
    }

    /// Top right: more for the files (AirDrop, Finder), in a menu.
    private var moreButton: some View {
        Button {
            ShelfMoreMenu.show([
                .init(title: "AirDrop…", symbol: "square.and.arrow.up") { actions.airDrop(store.items.map(\.url)) },
                .init(title: "Show in Finder", symbol: "folder") { actions.reveal(store.items) },
                .init(title: "Show All", symbol: "square.grid.2x2") { showAll() },
            ])
        } label: {
            Label("More", systemImage: "ellipsis")
                .font(.islandSymbol(.small, weight: .bold))
        }
        .buttonStyle(.islandIcon(isFilled: true, size: IslandStyle.Size.smallControl))
        .help("More")
    }

    /// Under the stack: "Show All", centered. An empty shelf (files are
    /// being dragged in) has nothing to show; it offers a small AirDrop
    /// zone in the corner instead, to send them right away.
    private var buttons: some View {
        HStack(spacing: 0) {
            if store.items.isEmpty {
                IslandDropZone(symbol: "dot.radiowaves.left.and.right", title: Self.airDropZone, isCompact: true) {
                    actions.airDrop($0.map(\.url))
                }
                .help("Drop here to AirDrop")
                Spacer(minLength: 0)
            } else {
                Button("Show All", action: showAll)
                    .buttonStyle(.islandText)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: IslandStyle.Size.control)
    }

    private func showAll() {
        withAnimation(IslandStyle.openAnimation) {
            presentation.showsAll = true
        }
    }
}

/// Every file on the shelf in a row, at the standard width.
struct ShelfListView: View {
    /// The header line, one row of tiles, and the bottom margin. Header
    /// text and tile content touch the margins; button capsules and tile
    /// fills, shown on hover (buttons) or selection (tiles), reach into them.
    static let contentHeight = IslandStyle.Size.labelLine + IslandStyle.Spacing.m + ShelfTile.contentHeight + IslandStyle.Spacing.content

    var store: ShelfStore
    var actions: ShelfActions

    @Environment(\.isDraggingFiles) private var isDraggingFiles
    /// Clicking a file selects it, like in Finder; double-clicking opens it.
    @State private var selection: ShelfItem.ID?
    /// Width of the row of tiles, which the tiles may not fill.
    @State private var rowWidth: CGFloat = 0

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
                                onOpen: actions.open,
                                onReveal: { actions.reveal([$0]) },
                                onAirDrop: { actions.airDrop([$0.url]) },
                                onRemove: actions.remove,
                                onDraggedOut: { actions.draggedOut([$0], $1) }
                            )
                        }
                    }
                    // Fills the row, so a click after the last tile lands
                    // here (the scroll view doesn't pass it to the
                    // background) and clears the selection; tiles take
                    // their own clicks first.
                    .frame(minWidth: rowWidth, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { selection = nil }
                }
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { rowWidth = $0 }
                // Tile content touches the margins; the tile's padding,
                // where its selection fill shows, reaches into them.
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
                Button("Show in Finder") { actions.reveal([item]) }
                Button("AirDrop…") { actions.airDrop([item.url]) }
                Button("Remove") {
                    selection = nil
                    actions.remove(item)
                }
            } else {
                Text(store.items.count == 1 ? "1 file" : "\(store.items.count) files")
                    .foregroundStyle(.secondary)
                Spacer(minLength: IslandStyle.Spacing.s)
                Button("AirDrop All…") {
                    actions.airDrop(store.items.map(\.url))
                }
                Button("Clear", action: actions.clear)
            }
        }
        .font(.islandLabel)
        .buttonStyle(.islandText)
        // Borderless buttons: their text, not their hover capsule, lines
        // up with the margins, like the label on the left.
        .padding(.trailing, -IslandStyle.Spacing.s)
        .padding(.vertical, -IslandTextButtonStyle.verticalInset)
    }

    /// While files are dragged in: dropped anywhere on the island, they
    /// stay on the shelf (its border shows it); on the AirDrop zone, they
    /// are sent right away.
    private var dropZones: some View {
        HStack(spacing: IslandStyle.Spacing.m) {
            ShelfDropHint()
            IslandDropZone(symbol: "dot.radiowaves.left.and.right", title: ShelfStackView.airDropZone) { actions.airDrop($0.map(\.url)) }
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
    var onDraggedOut: (ShelfItem, ShelfDrag.Outcome) -> Void

    @State private var isDragging = false
    @Environment(\.beginDragOut) private var beginDragOut

    var body: some View {
        VStack(spacing: IslandStyle.Spacing.xs) {
            ShelfThumbnail(url: item.url, side: IslandStyle.Size.thumbnail)
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
        // Only the selection shows, as in Finder: no fill on hover.
        .background(
            RoundedRectangle(cornerRadius: IslandStyle.Radius.medium, style: .continuous)
                .fill(isSelected ? IslandSignal.selection : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onOpen(item) }
        .onTapGesture { onSelect(item) }
        // Drag the file out (to Finder, Mail, a browser, a chat…). A Finder
        // drop on the same volume moves it (Cut + Paste); dropped anywhere,
        // it leaves the shelf.
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { _ in
                    guard !isDragging else { return }
                    isDragging = ShelfDrag.begin([item]) { operation in
                        isDragging = false
                        let outcome = ShelfDrag.outcome(of: operation)
                        if outcome != .none {
                            onDraggedOut(item, outcome)
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

/// Pop-up menu at the pointer, for the stack's "More" button. An AppKit
/// menu, like the audio output picker: the panel never becomes key.
@MainActor
private enum ShelfMoreMenu {
    struct Item {
        let title: String
        let symbol: String
        let action: () -> Void
    }

    /// Menu items' target; kept alive while the menu is up.
    private static var target: Target?

    static func show(_ items: [Item]) {
        let target = Target(items: items)
        self.target = target
        let menu = NSMenu()
        for (index, item) in items.enumerated() {
            let menuItem = NSMenuItem(title: item.title, action: #selector(Target.perform(_:)), keyEquivalent: "")
            menuItem.target = target
            menuItem.tag = index
            menuItem.image = NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil)
            menu.addItem(menuItem)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private final class Target: NSObject {
        let items: [Item]

        init(items: [Item]) {
            self.items = items
        }

        @objc func perform(_ menuItem: NSMenuItem) {
            MainActor.assumeIsolated {
                items[menuItem.tag].action()
            }
        }
    }
}

/// What the shelf shows while files are dragged in: the island itself is
/// the drop target, so no zone of its own, only words.
private struct ShelfDropHint: View {
    @Environment(\.isIslandDropTargeted) private var isTargeted

    var body: some View {
        Text("Drop here")
            .font(.islandHeadline)
            .foregroundStyle(isTargeted ? .primary : .secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Quick Look thumbnail (image, PDF, video frame…), or the file's icon
/// while it loads or when there is none. Thumbnails are cached
/// (`ShelfThumbnails`), so reopening the island shows them right away.
private struct ShelfThumbnail: View {
    let url: URL
    let side: CGFloat
    @State private var thumbnail: NSImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Image(nsImage: thumbnail ?? ShelfThumbnails.cached(for: url, side: side, scale: displayScale) ?? NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .task(id: url) {
                thumbnail = await ShelfThumbnails.thumbnail(for: url, side: side, scale: displayScale)
            }
    }
}
