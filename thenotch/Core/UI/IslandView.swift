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

    var body: some View {
        let expanded = state.isExpanded
        let size = expanded ? state.expandedSize : state.compactSize

        ZStack(alignment: .top) {
            NotchShape(topRadius: expanded ? 14 : 0, bottomRadius: expanded ? 22 : 8)
                .fill(Color.black)

            if expanded {
                expandedContent
                    // Leave room for the notch at the top.
                    .padding(.top, state.notchSize.height + 8)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
            } else if let module = state.currentModule {
                compactContent(module)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
        .overlay {
            if expanded { dropHighlight }
        }
        .overlay(alignment: .topLeading) {
            if expanded { moduleSwitcher }
        }
        // Only reachable while expanded: the panel ignores the mouse otherwise.
        .onDrop(of: [.fileURL], isTargeted: Binding(
            get: { state.isDropTargeted },
            set: { state.isDropTargeted = $0 }
        ), perform: drop)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.38, dampingFraction: 0.8), value: state.activities.current)
    }

    /// Wings left and right of the notch; the middle stays clear for it.
    private func compactContent(_ module: any IslandModule) -> some View {
        HStack(spacing: 0) {
            module.compactLeading()
                .frame(width: IslandState.wingWidth)
            Spacer(minLength: state.notchSize.width)
            module.compactTrailing()
                .frame(width: IslandState.wingWidth)
        }
        .frame(height: state.notchSize.height)
    }

    /// Outline showing where to drop while files are dragged.
    @ViewBuilder
    private var dropHighlight: some View {
        if state.isDraggingFiles {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    .white.opacity(state.isDropTargeted ? 0.7 : 0.3),
                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                )
                .padding(.top, state.notchSize.height + 4)
                .padding([.horizontal, .bottom], 10)
                .allowsHitTesting(false)
        }
    }

    /// One button per module, in the band left of the notch.
    @ViewBuilder
    private var moduleSwitcher: some View {
        if state.modules.count > 1 {
            HStack(spacing: 2) {
                ForEach(state.modules, id: \.id) { module in
                    let kind = ModuleKind(rawValue: module.id)
                    let isSelected = module.id == state.expandedModule?.id
                    Button {
                        state.pinnedModuleID = module.id
                        module.islandDidExpand()
                    } label: {
                        Image(systemName: kind?.symbol ?? "circle")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(isSelected ? 1 : 0.4))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(kind?.title ?? module.id)
                }
            }
            .padding(.leading, 20)
            .frame(height: state.notchSize.height)
        }
    }

    private func drop(_ providers: [NSItemProvider]) -> Bool {
        guard let receiver = state.expandedModule as? any FileDropReceiving else { return false }
        Task { @MainActor in
            let urls = await FileDrop.loadFileURLs(from: providers)
            if !urls.isEmpty {
                receiver.receive(urls)
            }
        }
        return true
    }

    @ViewBuilder
    private var expandedContent: some View {
        if let module = state.expandedModule {
            module.expandedView()
        } else {
            Text("Nothing to show")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}
