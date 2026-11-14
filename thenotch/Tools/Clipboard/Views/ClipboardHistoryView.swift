//
//  ClipboardHistoryView.swift
//  thenotch
//

import SwiftUI

/// The history inside the island: a search field over a one-line-per-row
/// list, on the island's black with its tokens.
struct ClipboardHistoryView: View {
    @Bindable var model: ClipboardHistoryModel

    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: IslandStyle.Spacing.s) {
            searchField
            if let issue = model.store.lastStorageIssue {
                issueBanner(issue)
            }
            content
        }
        .islandContentMargins()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { searchFocused = true }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            // The island panel becomes key when this view is shown; other windows don't count.
            guard (note.object as? NSWindow) is IslandPanel else { return }
            searchFocused = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Clipboard history")
    }

    private var searchField: some View {
        HStack(spacing: IslandStyle.Spacing.s) {
            Image(systemName: "magnifyingglass")
                .font(.islandSymbol(.compact, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search", text: $model.query)
                .textFieldStyle(.plain)
                .font(.islandLabel)
                .focused($searchFocused)
                .accessibilityLabel("Search clipboard history")
            if !model.query.isEmpty {
                Button {
                    model.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.islandSymbol(.compact))
                        .foregroundStyle(.secondary)
                        .frame(width: IslandStyle.Size.smallControl, height: IslandStyle.Size.smallControl)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, IslandStyle.Spacing.s)
        .frame(height: IslandStyle.Size.control)
        .background(.island(.hover), in: RoundedRectangle(cornerRadius: IslandStyle.Radius.medium, style: .continuous))
        .overlay {
            // The field's focus indicator (HIG Focus and selection: a ring
            // for a text field, a highlight for a list row).
            if searchFocused {
                RoundedRectangle(cornerRadius: IslandStyle.Radius.medium, style: .continuous)
                    .strokeBorder(.island(.outline), lineWidth: IslandStyle.Size.dropBorder)
            }
        }
        .onChange(of: model.query) { _, _ in
            // The first match is the one Return pastes.
            if let first = model.items.first { model.select(first.id) }
        }
    }

    @ViewBuilder private var content: some View {
        let items = model.items
        if !model.store.isLoaded && items.isEmpty {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Loading")
        } else if items.isEmpty {
            let searching = !model.query.trimmingCharacters(in: .whitespaces).isEmpty
            VStack(spacing: IslandStyle.Spacing.xs) {
                Image(systemName: searching ? "magnifyingglass" : "doc.on.clipboard")
                    .font(.islandSymbol(.large))
                    .accessibilityHidden(true)
                Text(searching ? "No matches" : "Nothing copied yet")
                    .font(.islandHeadline)
            }
            .foregroundStyle(.secondary)
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
                LazyVStack(spacing: IslandStyle.Spacing.xxs) {
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
            }
            .scrollIndicators(.never)
            .onChange(of: model.scrollRequest) { _, _ in
                guard let selected else { return }
                // No animation: arrow keys repeat, and motion on a frequent
                // interaction only makes people wait (HIG Motion).
                proxy.scrollTo(selected)
            }
        }
    }

    private func issueBanner(_ issue: ClipboardStore.StorageIssue) -> some View {
        Label(issue.message, systemImage: "exclamationmark.triangle.fill")
            .font(.islandLabel)
            .foregroundStyle(IslandSignal.attention)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
