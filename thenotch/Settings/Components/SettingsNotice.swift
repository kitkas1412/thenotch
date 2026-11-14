//
//  SettingsNotice.swift
//  thenotch
//

import SwiftUI

/// A status under a setting, with a symbol so it isn't told by color
/// alone, and the action that resolves it.
struct SettingsNotice: View {
    enum Kind {
        case ok, actionNeeded, problem

        var symbol: String {
            switch self {
            case .ok: "checkmark.circle.fill"
            case .actionNeeded: "exclamationmark.triangle.fill"
            case .problem: "xmark.octagon.fill"
            }
        }

        var tint: Color {
            switch self {
            case .ok: .green
            case .actionNeeded: .yellow
            case .problem: .red
            }
        }
    }

    let text: String
    let kind: Kind
    var action: (title: String, perform: () -> Void)?

    init(_ text: String, kind: Kind, action: (String, () -> Void)? = nil) {
        self.text = text
        self.kind = kind
        self.action = action.map { (title: $0.0, perform: $0.1) }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: kind.symbol)
                .foregroundStyle(kind.tint)
                .accessibilityHidden(true)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let action {
                Button(action.title, action: action.perform)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
