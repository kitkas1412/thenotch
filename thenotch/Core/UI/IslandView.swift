//
//  IslandView.swift
//  thenotch
//
//  Created by Nguyễn Đình Đức on 3/10/26.
//

import SwiftUI

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
