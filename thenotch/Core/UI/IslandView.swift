//
//  IslandView.swift
//  thenotch
//
//  Created by Nguyễn Đình Đức on 3/10/26.
//

import SwiftUI

/// Island content, pinned to the top center of the (larger, fixed-size) panel.
struct IslandView: View {
    var state: IslandState

    var body: some View {
        NotchShape(topRadius: 0, bottomRadius: 8)
            .fill(Color.black)
            .frame(width: state.notchSize.width, height: state.notchSize.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
