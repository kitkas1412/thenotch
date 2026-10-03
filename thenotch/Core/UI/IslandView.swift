//
//  IslandView.swift
//  thenotch
//
//  Created by Nguyễn Đình Đức on 3/10/26.
//

import SwiftUI
import UniformTypeIdentifiers

/// Island content, pinned to the top center of the (larger, fixed-size) panel.
/// Size and corner radii animate between the compact and expanded modes.
struct IslandView: View {
    var state: IslandState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    // Leave room for the notch at the top, and keep out of
                    // the flares: the island's visible sides are inset by
                    // them, and margins are measured from what's visible.
                    .padding(.top, state.notchSize.height + IslandStyle.Spacing.content)
                    .padding(.horizontal, IslandStyle.Radius.islandFlare)
                    // Always laid out at the open size, so it doesn't reflow
                    // while the island grows or shrinks around it.
                    .frame(width: state.expandedSize.width, height: state.expandedSize.height, alignment: .top)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
            } else if let module = state.currentModule {
                compactContent(module)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
        // Content lives inside the island: the island's own (animating)
        // shape masks it, so it is revealed as the island opens and
        // covered as it closes, never left fading outside it.
        .clipShape(NotchShape(topRadius: radii.top, bottomRadius: radii.bottom))
        // The island is black in every appearance, like the Dynamic Island;
        // semantic styles then resolve to light-on-dark (and follow
        // Increase Contrast).
        .environment(\.colorScheme, .dark)
        // Only reachable while expanded: the panel ignores the mouse otherwise.
        // Modules may add their own drop zones inside; this catches the rest.
        .onDrop(of: FileDrop.acceptedTypes, isTargeted: nil, perform: drop)
        .environment(\.isDraggingFiles, state.isDraggingFiles)
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

    private func drop(_ providers: [NSItemProvider]) -> Bool {
        guard let receiver = state.expandedModule as? any FileDropReceiving else { return false }
        Task { @MainActor in
            let files = await FileDrop.loadFiles(from: providers)
            if !files.isEmpty {
                receiver.receive(files)
            }
        }
        return true
    }

    @ViewBuilder
    private var expandedContent: some View {
        if let module = state.expandedModule {
            module.expandedView()
        } else {
            // Every module is switched off.
            IslandEmptyState(title: "No modules are on", message: "Turn one on in thenotch Settings.")
        }
    }
}
