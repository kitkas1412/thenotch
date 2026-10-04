//
//  IslandView.swift
//  thenotch
//
//  Created by Nguyễn Đình Đức on 3/10/26.
//

import os
import SwiftUI
import UniformTypeIdentifiers

/// Island content, pinned to the top center of the (larger, fixed-size) panel.
/// Size and corner radii animate between the compact and expanded modes.
struct IslandView: View {
    var state: IslandState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Drop zones shown by the module, and the one files are over.
    @State private var dropTargets: [IslandDropTarget] = []
    @State private var targetedDropZone: String?
    /// Dragged files are over the island.
    @State private var isDropTargeted = false

    private static let expandedRadii = (top: IslandStyle.Radius.islandFlare, bottom: IslandStyle.Radius.island)

    var body: some View {
        let expanded = state.isExpanded
        let size = expanded ? state.expandedSize : state.compactSize
        let radii = expanded ? Self.expandedRadii : (top: CGFloat(0), bottom: state.compactCornerRadius)

        ZStack(alignment: .top) {
            NotchShape(topRadius: radii.top, bottomRadius: radii.bottom)
                .fill(IslandColors.surface)

            if expanded {
                expandedContent
                    // Leave room for the notch at the top, and for the tab
                    // row if there is one. (Each page keeps out of the
                    // flares itself: `ModulePage`.)
                    .padding(.top, state.expandedContentTop)
                    // Always laid out at the open size, so it doesn't reflow
                    // while the island grows or shrinks around it.
                    .frame(width: state.expandedSize.width, height: state.expandedSize.height, alignment: .top)
                    // Tabs sit in the band left of the notch, unused
                    // otherwise, or in a row under it when the island is
                    // too narrow (the shelf's stack); aligned with the
                    // content's left margin either way. Switching between
                    // the two, they move with the island's spring.
                    .overlay(alignment: .topLeading) {
                        if state.showsTabs {
                            let besideNotch = state.tabsBesideNotch
                            ModuleTabs(state: state)
                                .frame(height: besideNotch ? state.notchSize.height : IslandStyle.Size.control)
                                .padding(.top, besideNotch ? 0 : state.notchSize.height + IslandStyle.Spacing.content)
                                .padding(.leading, IslandStyle.Radius.islandFlare + IslandStyle.Spacing.content)
                                .transition(.opacity)
                        }
                    }
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
            } else if let module = state.currentModule {
                compactContent(module)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
        // While files are dragged in, the island is the drop target: a
        // border that turns thick and white once they are over it (and not
        // over a drop zone of its own, such as AirDrop).
        .overlay {
            if expanded && state.isDraggingFiles {
                let isActive = isDropTargeted && targetedDropZone == nil
                NotchShape(topRadius: radii.top, bottomRadius: radii.bottom, isOpenAtTop: true)
                    // Centered on the edge, and the clip shape below cuts
                    // the outer half: twice the width shows the width.
                    .stroke(
                        .island(isActive ? .outlineActive : .outline),
                        lineWidth: 2 * (isActive ? IslandStyle.Size.dropBorderActive : IslandStyle.Size.dropBorder)
                    )
                    .allowsHitTesting(false)
            }
        }
        // Content lives inside the island: the island's own (animating)
        // shape masks it, so it is revealed as the island opens and
        // covered as it closes, never left fading outside it.
        .clipShape(NotchShape(topRadius: radii.top, bottomRadius: radii.bottom))
        // The island is black in every appearance, like the Dynamic Island;
        // semantic styles then resolve to light-on-dark (and follow
        // Increase Contrast).
        .environment(\.colorScheme, .dark)
        // Only reachable while expanded: the panel ignores the mouse otherwise.
        // The one drop target, outside the clip shape: it hands files to
        // the module's drop zone under the pointer, or to the module.
        .onPreferenceChange(IslandDropTarget.Key.self) { dropTargets = $0 }
        .coordinateSpace(name: IslandDropTarget.coordinateSpace)
        .onDrop(of: FileDrop.acceptedTypes, delegate: IslandDropDelegate(
            state: state,
            targets: dropTargets,
            targetedZone: $targetedDropZone,
            isTargeted: $isDropTargeted
        ))
        .onChange(of: state.isDraggingFiles) { _, isDragging in
            if !isDragging {
                isDropTargeted = false
            }
        }
        .environment(\.isDraggingFiles, state.isDraggingFiles)
        .environment(\.targetedDropZone, targetedDropZone)
        .environment(\.isIslandDropTargeted, isDropTargeted && targetedDropZone == nil)
        .environment(\.allowsAmbientAnimation, state.ambient.allowsAnimation)
        .environment(\.beginDragOut) { [state] in
            state.onDragOutBegan?()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(IslandStyle.openAnimation, value: state.activities.current)
    }

    /// Wings left and right of the notch; the middle stays clear for it.
    /// Content sits snug against the notch so both wings read as one piece
    /// of information (HIG Live Activities › Compact presentation), with
    /// equal padding on every side (`IslandState.compactPadding`).
    private func compactContent(_ module: any IslandModule) -> some View {
        let contentSize = CGSize(width: module.compactContentWidth, height: IslandStyle.Size.compactContent)
        return HStack(spacing: 0) {
            module.compactLeading()
                .frame(width: contentSize.width, height: contentSize.height, alignment: .trailing)
                .padding(state.compactPadding)
            Spacer(minLength: state.notchSize.width)
            module.compactTrailing()
                .frame(width: contentSize.width, height: contentSize.height, alignment: .leading)
                .padding(state.compactPadding)
        }
        .frame(height: state.notchSize.height)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var expandedContent: some View {
        let tabs = state.showsTabs ? state.tabModules : []
        if !reduceMotion, let shown = state.expandedModule,
           let index = tabs.firstIndex(where: { $0.id == shown.id }) {
            ModulePager(modules: tabs, index: index)
        } else if let module = state.expandedModule {
            ModulePage(module: module)
                // Reduce Motion, or no tabs: a new module fades in.
                .id(module.id)
                .transition(.opacity)
        } else {
            // Every module is switched off.
            ModulePage {
                IslandEmptyState(title: "No modules are on", message: "Turn one on in thenotch Settings.")
            }
        }
    }
}

/// One module's content, the island's full width, kept out of the flares:
/// the island's visible sides are inset by them, and margins are measured
/// from what's visible.
private struct ModulePage<Content: View>: View {
    var width = IslandState.expandedWidth
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, IslandStyle.Radius.islandFlare)
            .frame(width: width, alignment: .top)
    }
}

extension ModulePage where Content == AnyView {
    init(module: any IslandModule) {
        self.init(width: module.expandedWidth) { module.expandedView() }
    }
}

/// The tabs' modules side by side, scrolled to the shown one: switching
/// tabs slides the content over, toward the tab's side (HIG Motion: motion
/// that shows where content comes from), while the island resizes to the
/// new page (the shelf's stack is narrower). The island's clip shape hides
/// the other pages; they don't take the pointer or VoiceOver. Pages keep
/// their state (e.g. the shelf's selection) while tabs switch.
private struct ModulePager: View {
    let modules: [any IslandModule]
    let index: Int

    var body: some View {
        let widths = modules.map(\.expandedWidth)
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(modules.enumerated()), id: \.element.id) { offset, module in
                let isShown = offset == index
                ModulePage(module: module)
                    .allowsHitTesting(isShown)
                    .accessibilityHidden(!isShown)
            }
        }
        .offset(x: -widths.prefix(index).reduce(0, +))
        .frame(width: widths[index], alignment: .leading)
    }
}

/// Takes files dropped anywhere on the island: on a drop zone, they go to
/// that zone; elsewhere, to the shown module if it takes files.
private struct IslandDropDelegate: DropDelegate {
    let state: IslandState
    let targets: [IslandDropTarget]
    @Binding var targetedZone: String?
    @Binding var isTargeted: Bool

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: FileDrop.acceptedTypes)
    }

    func dropEntered(info: DropInfo) {
        isTargeted = true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let zone = IslandDropTarget.target(at: info.location, in: targets)?.id
        if zone != targetedZone {
            targetedZone = zone
        }
        if !isTargeted {
            isTargeted = true
        }
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        targetedZone = nil
        isTargeted = false
    }

    func performDrop(info: DropInfo) -> Bool {
        targetedZone = nil
        isTargeted = false
        let perform: ([DroppedFile]) -> Void
        if let target = IslandDropTarget.target(at: info.location, in: targets) {
            Log.drop.notice("Drop on the \(target.id, privacy: .public) zone")
            perform = target.perform
        } else if let receiver = state.expandedModule as? any FileDropReceiving {
            perform = { receiver.receive($0) }
        } else {
            return false
        }
        let providers = info.itemProviders(for: FileDrop.acceptedTypes)
        Task { @MainActor in
            let files = await FileDrop.loadFiles(from: providers)
            if !files.isEmpty {
                perform(files)
            }
        }
        return true
    }
}

/// One tab per module with something to show, so people can switch
/// between them (e.g. from the player to the shelf). The shown module's
/// tab is filled.
private struct ModuleTabs: View {
    var state: IslandState

    var body: some View {
        let shownID = state.expandedModule?.id
        HStack(spacing: IslandStyle.Spacing.xs) {
            ForEach(state.tabModules, id: \.id) { module in
                let kind = ModuleKind(rawValue: module.id)
                let isShown = module.id == shownID
                Button {
                    withAnimation(IslandStyle.openAnimation) {
                        state.select(module.id)
                    }
                } label: {
                    Label(kind?.title ?? module.id, systemImage: kind?.symbol ?? "circle")
                        .font(.islandSymbol(.compact, weight: .semibold))
                }
                .buttonStyle(.islandIcon(isSelected: isShown))
                .help(kind?.title ?? module.id)
                .accessibilityAddTraits(isShown ? .isSelected : [])
            }
        }
    }
}
