//
//  SystemMonitorTool.swift
//  thenotch
//

import AppKit
import Observation
import SwiftUI

/// CPU, memory, network, disk and battery in the menu bar: a status item
/// with the chosen metrics and a popover with all of them.
@MainActor
final class SystemMonitorTool: NSObject, Tool, NSPopoverDelegate {
    let id = ToolKind.systemMonitor.id
    private let settings: AppSettings
    private let sampler = SystemSampler()
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var isRunning = false
    /// Invalidates a queued observation callback of an earlier start.
    private var trackingGeneration = 0
    private var lastTitle: NSAttributedString?
    private var lastAccessibilityLabel: String?

    init(settings: AppSettings) {
        self.settings = settings
        super.init()
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        trackingGeneration += 1
        lastTitle = nil
        lastAccessibilityLabel = nil

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "thenotch.systemMonitor"
        if let button = item.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.imagePosition = .imageOnly
            button.setAccessibilityRole(.button)
        }
        statusItem = item

        let popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        let content = NSHostingController(rootView: SystemMonitorPopoverView(sampler: sampler))
        content.sizingOptions = .preferredContentSize
        popover.contentViewController = content
        self.popover = popover

        sampler.interval = settings.systemMonitorInterval.seconds
        sampler.start()
        track()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        trackingGeneration += 1
        sampler.stop()
        popover?.close()
        popover = nil
        sampler.isPopoverOpen = false
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
    }

    // MARK: Live updates

    /// Follows the interval and the metrics, and redraws the label.
    private func track() {
        guard isRunning else { return }
        let generation = trackingGeneration
        withObservationTracking {
            _ = settings.systemMonitorInterval
            _ = settings.systemMonitorMetrics
            _ = sampler.snapshot
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.isRunning, self.trackingGeneration == generation else { return }
                self.sampler.interval = self.settings.systemMonitorInterval.seconds
                self.updateLabel()
                self.track()
            }
        }
        updateLabel()
    }

    /// Draws the chosen metrics as the button's title (the icon alone when
    /// none is chosen); the item's variable length follows it.
    private func updateLabel() {
        guard let button = statusItem?.button else { return }
        let metrics = settings.systemMonitorMetrics
        let title = metrics.isEmpty ? NSAttributedString()
            : SystemMonitorMenuBarLabel.title(snapshot: sampler.snapshot, metrics: metrics)
        if metrics.isEmpty {
            if button.image == nil {
                let image = NSImage(systemSymbolName: ToolKind.systemMonitor.symbol, accessibilityDescription: nil)
                image?.isTemplate = true
                button.image = image
                button.imagePosition = .imageOnly
            }
        } else if button.image != nil {
            button.image = nil
            button.imagePosition = .noImage
        }
        // Setting the title relays the item out: only when it changed.
        if lastTitle != title {
            lastTitle = title
            button.attributedTitle = title
        }
        let label = SystemMonitorMenuBarLabel.accessibilityLabel(snapshot: sampler.snapshot, metrics: metrics)
        if lastAccessibilityLabel != label {
            lastAccessibilityLabel = label
            button.setAccessibilityLabel(label)
        }
    }

    // MARK: Popover

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        guard let popover else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }

    func popoverDidShow(_ notification: Notification) {
        sampler.isPopoverOpen = true
    }

    func popoverDidClose(_ notification: Notification) {
        sampler.isPopoverOpen = false
    }
}
