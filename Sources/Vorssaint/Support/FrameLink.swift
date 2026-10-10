// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import QuartzCore

/// Calls back once per display frame on the main run loop until invalidated.
/// A `CADisplayLink` from macOS 14 on; before that AppKit offers none, so a
/// timer at the display's refresh rate stands in for it.
final class FrameLink {
    enum Source {
        case view(NSView)
        case screen(NSScreen)
    }

    /// When the frame being prepared was due to start.
    private(set) var timestamp: CFTimeInterval = 0
    /// When the frame being prepared will show.
    private(set) var targetTimestamp: CFTimeInterval = 0
    /// The time between frames.
    private(set) var duration: CFTimeInterval = 0

    /// The `CADisplayLink` behind this link, when there is one.
    private(set) var native: AnyObject?
    private var timer: Timer?
    private let onFrame: (FrameLink) -> Void

    /// `maximumRate` caps the callbacks per second; nil follows the display.
    init(source: Source, maximumRate: Float? = nil, onFrame: @escaping (FrameLink) -> Void) {
        self.onFrame = onFrame
        if #available(macOS 14.0, *) {
            let target = Target(link: self)
            let link: CADisplayLink
            switch source {
            case .view(let view):
                link = view.displayLink(target: target, selector: #selector(Target.fire(_:)))
            case .screen(let screen):
                link = screen.displayLink(target: target, selector: #selector(Target.fire(_:)))
            }
            if let maximumRate {
                link.preferredFrameRateRange = CAFrameRateRange(
                    minimum: maximumRate / 2, maximum: maximumRate, preferred: maximumRate)
            }
            link.add(to: .main, forMode: .common)
            native = link
        } else {
            let screen: NSScreen?
            switch source {
            case .view(let view): screen = view.window?.screen ?? NSScreen.main
            case .screen(let candidate): screen = candidate
            }
            let refresh = Float(screen?.maximumFramesPerSecond ?? 0)
            let display = refresh > 0 ? refresh : 60
            let interval = 1 / CFTimeInterval(min(maximumRate ?? display, display))
            duration = interval
            let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.timestamp = CACurrentMediaTime()
                self.targetTimestamp = self.timestamp + interval
                self.onFrame(self)
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    func invalidate() {
        if #available(macOS 14.0, *) {
            (native as? CADisplayLink)?.invalidate()
        }
        native = nil
        timer?.invalidate()
        timer = nil
    }

    deinit { invalidate() }

    /// A display link retains its target. The link is held weakly, so letting
    /// go of a `FrameLink` stops it even while it runs.
    @available(macOS 14.0, *)
    private final class Target: NSObject {
        weak var link: FrameLink?
        init(link: FrameLink) { self.link = link }

        @objc func fire(_ sender: CADisplayLink) {
            guard let link else {
                sender.invalidate()
                return
            }
            link.timestamp = sender.timestamp
            link.targetTimestamp = sender.targetTimestamp
            link.duration = sender.duration
            link.onFrame(link)
        }
    }
}
