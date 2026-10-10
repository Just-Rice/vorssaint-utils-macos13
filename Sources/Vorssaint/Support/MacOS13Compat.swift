// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

// Stand-ins for SwiftUI API that first shipped in macOS 14, so the app keeps
// building and running on macOS 13. Each one calls the real API when it exists.

private struct OnChangeCompatModifier<Value: Equatable>: ViewModifier {
    let value: Value
    let initial: Bool
    let action: (Value, Value) -> Void

    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.onChange(of: value, initial: initial, action)
        } else {
            content
                .onAppear { if initial { action(value, value) } }
                // The capture list holds the value from before the change.
                .onChange(of: value) { [value] newValue in action(value, newValue) }
        }
    }
}

extension View {
    func onChangeCompat<Value: Equatable>(
        of value: Value, initial: Bool = false,
        _ action: @escaping (Value, Value) -> Void
    ) -> some View {
        modifier(OnChangeCompatModifier(value: value, initial: initial, action: action))
    }

    func onChangeCompat<Value: Equatable>(
        of value: Value, initial: Bool = false,
        _ action: @escaping () -> Void
    ) -> some View {
        modifier(OnChangeCompatModifier(value: value, initial: initial) { _, _ in action() })
    }
}

extension View {
    /// Swapping one SF Symbol for another; a plain fade before macOS 14.
    @ViewBuilder
    func symbolReplaceTransitionCompat() -> some View {
        if #available(macOS 14.0, *) {
            contentTransition(.symbolEffect(.replace))
        } else {
            contentTransition(.opacity)
        }
    }

    @ViewBuilder
    func symbolBounceCompat<Value: Equatable>(value: Value, speed: Double = 1) -> some View {
        if #available(macOS 14.0, *) {
            symbolEffect(.bounce, options: .speed(speed), value: value)
        } else {
            self
        }
    }

    @ViewBuilder
    func symbolVariableColorCompat(reversing: Bool = false, isActive: Bool) -> some View {
        if #available(macOS 14.0, *) {
            if reversing {
                symbolEffect(.variableColor.iterative.reversing, options: .repeating, isActive: isActive)
            } else {
                symbolEffect(.variableColor.iterative, options: .repeating, isActive: isActive)
            }
        } else {
            self
        }
    }

    /// Key handling on a focused view. macOS 13 has no equivalent, so the
    /// keys do nothing there and the pointer remains the way in.
    @ViewBuilder
    func onKeyPressCompat(_ key: KeyEquivalent, action: @escaping () -> Void) -> some View {
        if #available(macOS 14.0, *) {
            onKeyPress(key) { action(); return .handled }
        } else {
            self
        }
    }

    @ViewBuilder
    func focusableForEditingCompat() -> some View {
        if #available(macOS 14.0, *) {
            focusable(interactions: .edit)
        } else {
            focusable()
        }
    }

    @ViewBuilder
    func focusEffectDisabledCompat() -> some View {
        if #available(macOS 14.0, *) {
            focusEffectDisabled()
        } else {
            self
        }
    }

    @ViewBuilder
    func capsuleButtonBorderCompat() -> some View {
        if #available(macOS 14.0, *) {
            buttonBorderShape(.capsule)
        } else {
            buttonBorderShape(.roundedRectangle)
        }
    }

    @ViewBuilder
    func blurReplaceTransitionCompat() -> some View {
        if #available(macOS 14.0, *) {
            transition(.blurReplace)
        } else {
            transition(.opacity)
        }
    }

    /// A transaction scoped to one value's changes. The unscoped form macOS 13
    /// offers would touch every update, so the change goes unanimated there.
    @ViewBuilder
    func transactionCompat<Value: Equatable>(
        value: Value, _ transform: @escaping (inout Transaction) -> Void
    ) -> some View {
        if #available(macOS 14.0, *) {
            transaction(value: value, transform)
        } else {
            self
        }
    }

    /// A short sideways nudge that settles back; skipped before macOS 14.
    @ViewBuilder
    func nudgeCompat(displacement: CGFloat, trigger: Int) -> some View {
        if #available(macOS 14.0, *) {
            keyframeAnimator(initialValue: CGFloat.zero, trigger: trigger) { view, travel in
                view.offset(x: displacement * travel)
            } keyframes: { _ in
                CubicKeyframe(8, duration: 0.09)
                SpringKeyframe(0, duration: 0.25, spring: .smooth)
            }
        } else {
            self
        }
    }
}

extension ShapeStyle where Self == AnyShapeStyle {
    /// `.background.secondary`, or the nearest system colour before macOS 14.
    static var backgroundSecondaryCompat: AnyShapeStyle {
        if #available(macOS 14.0, *) {
            return AnyShapeStyle(.background.secondary)
        }
        return AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
    }
}

/// `ContentUnavailableView` with a title and symbol, drawn by hand before macOS 14.
struct ContentUnavailableCompat: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        if #available(macOS 14.0, *) {
            ContentUnavailableView(title, systemImage: systemImage)
        } else {
            VStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }
}

/// `withAnimation` with a completion. Before macOS 14 the completion runs
/// after `duration`, which the caller knows from the animation it passed.
func withAnimationCompat(
    _ animation: Animation?, duration: TimeInterval,
    _ body: () -> Void, completion: @escaping () -> Void
) {
    if #available(macOS 14.0, *) {
        withAnimation(animation, completionCriteria: .logicallyComplete, body, completion: completion)
    } else {
        withAnimation(animation, body)
        if animation == nil {
            completion()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: completion)
        }
    }
}
