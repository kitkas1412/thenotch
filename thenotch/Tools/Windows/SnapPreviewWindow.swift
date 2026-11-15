import AppKit

/// The translucent rectangle shown where a dragged window will land when it is released.
///
/// System chrome over other apps' windows, not the island: it uses system materials and colors
/// (see DESIGN.md), follows the system appearance, and never takes events or focus.
@MainActor
final class SnapPreviewWindow {
    private let window: SnapPreviewPanel
    private let content = SnapPreviewView()
    private var isShown = false
    /// Bumped on every show/hide so a finished fade-out can't hide a newer preview.
    private var generation = 0
    private var observer: NSObjectProtocol?

    private static let inset: CGFloat = 4
    private static let fadeIn: TimeInterval = 0.12
    private static let fadeOut: TimeInterval = 0.09
    private static let move: TimeInterval = 0.12

    init() {
        window = SnapPreviewPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                  backing: .buffered, defer: true)
        window.contentView = content
        // Above normal and floating windows (the dragged window is raised), below menus and the
        // status bar, so it never covers a menu being used.
        window.level = .modalPanel
        window.alphaValue = 0
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.content.refresh() }
        }
    }

    deinit {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    /// `frame` is the target window frame in global Cocoa coordinates.
    func show(frame: CGRect) {
        let target = frame.insetBy(dx: Self.inset, dy: Self.inset)
        guard target.width > 0, target.height > 0 else { return }
        generation += 1
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        content.refresh()

        if !isShown {
            isShown = true
            window.setFrame(target, display: true)
            window.alphaValue = 0
            window.orderFrontRegardless()
            fade(to: 1, duration: Self.fadeIn)
        } else {
            if window.alphaValue < 1 { fade(to: 1, duration: Self.fadeIn) }
            guard window.frame != target else { return }
            if reduceMotion {
                window.setFrame(target, display: true)
            } else {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = Self.move
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    window.animator().setFrame(target, display: true)
                }
            }
        }
    }

    /// Fades out and removes the window. Safe to call when hidden.
    func hide() {
        guard isShown else { return }
        isShown = false
        generation += 1
        let token = generation
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.fadeOut
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == token else { return }
                self.window.orderOut(nil)
            }
        })
    }

    private func fade(to alpha: CGFloat, duration: TimeInterval) {
        // Reduce Motion replaces movement with fades (HIG accessibility.md > Motion), so the
        // fade stays; only the frame animation is dropped.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            window.animator().alphaValue = alpha
        }
    }
}

/// Borderless panel that is click-through, never key or main, and absent from Mission Control and ⌘Tab.
@MainActor
private final class SnapPreviewPanel: NSPanel {
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask,
                  backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        animationBehavior = .none
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isExcludedFromWindowsMenu = true
        collectionBehavior = [.transient, .ignoresCycle, .canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Material, tint and border. Under Reduce Transparency the blur is replaced by a solid, mostly opaque
/// fill; under Increase Contrast the border is thicker and stronger.
@MainActor
private final class SnapPreviewView: NSView {
    private let effect = NSVisualEffectView()
    private let tint = NSView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.autoresizingMask = [.width, .height]
        tint.wantsLayer = true
        tint.autoresizingMask = [.width, .height]
        addSubview(effect)
        addSubview(tint)
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        effect.frame = bounds
        tint.frame = bounds
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }

    func refresh() {
        let workspace = NSWorkspace.shared
        let solid = workspace.accessibilityDisplayShouldReduceTransparency
        let contrast = workspace.accessibilityDisplayShouldIncreaseContrast
        // Matches window corners: larger from macOS 26.
        let radius: CGFloat = if #available(macOS 26, *) { 20 } else { 10 }
        layer?.cornerRadius = radius
        layer?.cornerCurve = .continuous
        effect.isHidden = solid
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let accent = NSColor.controlAccentColor
            tint.layer?.backgroundColor = (solid
                ? NSColor.windowBackgroundColor.blended(withFraction: 0.25, of: accent)?.withAlphaComponent(0.92)
                    ?? NSColor.windowBackgroundColor
                : accent.withAlphaComponent(contrast ? 0.3 : 0.18)).cgColor
            layer?.borderColor = (contrast ? NSColor.labelColor : accent.withAlphaComponent(0.6)).cgColor
        }
        layer?.borderWidth = contrast ? 2 : 1
    }
}
