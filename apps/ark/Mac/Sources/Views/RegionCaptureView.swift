import AppKit

/// A drag selection in viewport coordinates. WebKit's snapshot excludes the overlay.
final class RegionCaptureView: NSView {
    enum Mode { case area, element }
    enum Selection {
        case area(NSRect)
        case element(NSPoint)
    }

    private var start: NSPoint?
    private var selection = NSRect.zero
    private weak var page: NSView?
    private var mouseMonitor: Any?
    private let mode: Mode
    private let completion: (Selection) -> Void

    static func present(on page: NSView, mode: Mode, completion: @escaping (Selection) -> Void) -> RegionCaptureView? {
        guard let window = page.window, let container = page.superview,
              !container.subviews.contains(where: { $0 is RegionCaptureView }) else { return nil }
        let picker = RegionCaptureView(page: page, mode: mode, completion: completion)
        container.addSubview(picker, positioned: .above, relativeTo: page)
        window.makeFirstResponder(picker)
        return picker
    }

    init(page: NSView, mode: Mode, completion: @escaping (Selection) -> Void) {
        self.page = page
        self.mode = mode
        self.completion = completion
        super.init(frame: page.frame)
        autoresizingMask = [.width, .height]
        setAccessibilityLabel(mode == .area ? "Drag to select a page area. Press Escape to cancel."
                                             : "Click a page element. Press Escape to cancel.")
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, mouseMonitor == nil {
            mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .scrollWheel]) { [weak self] event in
                let handled = MainActor.assumeIsolated { self?.handleSelectionEvent(event) ?? false }
                return handled ? nil : event
            }
        } else if window == nil {
            if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
            mouseMonitor = nil
            if superview != nil { removeFromSuperview() }
        }
    }

    // SwiftUI hosts the page and can claim the window's hit test before AppKit reaches this view.
    private func handleSelectionEvent(_ event: NSEvent) -> Bool {
        guard let window, event.window === window else { return false }
        switch event.type {
        case .leftMouseDown:
            guard visibleRect.contains(convert(event.locationInWindow, from: nil)) else {
                dismiss()
                return false
            }
            mouseDown(with: event)
        case .leftMouseDragged:
            guard start != nil else { return false }
            mouseDragged(with: event)
        case .leftMouseUp:
            guard start != nil else { return false }
            mouseUp(with: event)
        default:
            return visibleRect.contains(convert(event.locationInWindow, from: nil))
        }
        return true
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        selection = .zero
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard mode == .area, let start else { return }
        let point = convert(event.locationInWindow, from: nil)
        selection = NSRect(x: min(start.x, point.x), y: min(start.y, point.y),
                           width: abs(start.x - point.x), height: abs(start.y - point.y))
            .integral.intersection(visibleRect)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if mode == .element {
            let point = convert(event.locationInWindow, from: nil)
            let inside = visibleRect.contains(point)
            dismiss()
            if inside { completion(.element(point)) }
            return
        }
        mouseDragged(with: event)
        let rect = selection
        dismiss()
        if rect.width >= 2, rect.height >= 2 { completion(.area(rect)) }
    }

    override func keyDown(with event: NSEvent) { interpretKeyEvents([event]) }

    override func cancelOperation(_ sender: Any?) { dismiss() }

    override func draw(_ dirtyRect: NSRect) {
        let shade = NSBezierPath(rect: bounds)
        if !selection.isEmpty { shade.appendRect(selection) }
        shade.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.35).setFill()
        shade.fill()
        if !selection.isEmpty {
            NSColor.white.setStroke()
            NSBezierPath(rect: selection.insetBy(dx: 0.5, dy: 0.5)).stroke()
        }
    }

    private func dismiss() {
        if let window, window.firstResponder === self { window.makeFirstResponder(page) }
        removeFromSuperview()
    }
}
