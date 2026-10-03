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
        let size = expanded ? state.expandedSize : state.notchSize

        ZStack(alignment: .top) {
            NotchShape(topRadius: expanded ? 14 : 0, bottomRadius: expanded ? 22 : 8)
                .fill(Color.black)

            if expanded {
                // Placeholder until modules (Now Playing, Battery…) exist.
                Text("Hello, Island")
                    .font(.headline)
                    .foregroundStyle(.white)
                    // Leave room for the notch at the top.
                    .padding(.top, state.notchSize.height + 8)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
            }
        }
        .frame(width: size.width, height: size.height)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
