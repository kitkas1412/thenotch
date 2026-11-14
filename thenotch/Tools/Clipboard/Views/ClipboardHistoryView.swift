//
//  ClipboardHistoryView.swift
//  thenotch
//

import SwiftUI

/// The history panel's content: a search field over the list. System
/// styles only (the panel sits on a material, unlike the island).
struct ClipboardHistoryView: View {
    @Bindable var model: ClipboardHistoryModel

    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            if let issue = model.store.lastStorageIssue {
                issueBanner(issue)
                Divider()
            }
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { searchFocused = true }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            // Only the history panel's own window.
            guard let window = model.window, notification.object as? NSWindow === window else { return }
            searchFocused = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Clipboard history")
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search clipboard history", text: $model.query)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($searchFocused)
                .accessibilityLabel("Search clipboard history")
            if !model.query.isEmpty {
                Button {
                    model.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .onChange(of: model.query) { _, _ in
            // The first match is the one Return pastes.
            if let first = model.items.first { model.select(first.id) }
        }
    }

    @ViewBuilder private var content: some View {
        let items = model.items
        if !model.store.isLoaded && items.isEmpty {
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading…").font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        } else if items.isEmpty {
            let searching = !model.query.trimmingCharacters(in: .whitespaces).isEmpty
            VStack(spacing: 6) {
                Image(systemName: searching ? "magnifyingglass" : "doc.on.clipboard")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                Text(searching ? "No matches" : "Nothing copied yet")
                    .font(.headline)
                if !searching {
                    Text("Things you copy show up here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        } else {
            list(items)
        }
    }

    private func list(_ items: [ClipboardItem]) -> some View {
        let selected = model.selectedItem?.id
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        ClipboardRow(
                            item: item,
                            store: model.store,
                            quickNumber: index < 9 ? index + 1 : nil,
                            isSelected: item.id == selected,
                            onChoose: { model.choose(item) },
                            onHover: { model.hover(item.id, at: NSEvent.mouseLocation) },
                            onDelete: { model.delete(item) }
                        )
                        .id(item.id)
                    }
                }
                .padding(6)
            }
            .onChange(of: model.scrollRequest) { _, _ in
                if let selected { proxy.scrollTo(selected) }
            }
        }
    }

    private func issueBanner(_ issue: ClipboardStore.StorageIssue) -> some View {
        Label(issue.message, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.secondary)
            .symbolRenderingMode(.multicolor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
    }
}
