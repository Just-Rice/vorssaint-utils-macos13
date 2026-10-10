// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Every yield goes through here. `yieldActivation(to:)` only hands over
/// activation this app holds, and Vorssaint (`LSUIElement`, non-activating
/// panels) usually holds none when a switch commits, so the yield gave away
/// nothing and the cooperative `activate(from:)` after it was refused.
/// Self-activating first gives the yield something to hand over.
enum ActivationHandoff {
    /// Our own activation notification arrives within a turn of the request.
    /// Past that, an activation of Vorssaint is the user opening one of its
    /// windows, which is a real use and stays in the switcher's history.
    private static let selfActivationWindow: CFTimeInterval = 1

    private static var lastSelfActivation: CFAbsoluteTime = 0

    /// Whether the activation of Vorssaint being reported right now is the one
    /// `yield(to:)` asked for on its way out. Main thread, like every `NSApp`
    /// call here and like the activation notifications that read it.
    static var isHandingOff: Bool {
        CFAbsoluteTimeGetCurrent() - lastSelfActivation < selfActivationWindow
    }

    static func yield(to app: NSRunningApplication) {
        // macOS 13 has no cooperative activation: any app may bring another
        // forward, so there is nothing to hand over.
        guard #available(macOS 14.0, *) else { return }
        lastSelfActivation = CFAbsoluteTimeGetCurrent()
        NSApp.activate(ignoringOtherApps: true)
        NSApp.yieldActivation(to: app)
    }
}

extension NSRunningApplication {
    /// `activate(from:options:)`, or the forced activation macOS 13 relies on.
    func activateCompat(from source: NSRunningApplication,
                        options: NSApplication.ActivationOptions) -> Bool {
        if #available(macOS 14.0, *) {
            return activate(from: source, options: options)
        }
        return activate(options: options.union(.activateIgnoringOtherApps))
    }
}
