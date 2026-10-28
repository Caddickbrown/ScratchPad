import SwiftUI
import ScratchpadCore

/// Settings keys shared by @AppStorage users.
enum SettingsKey {
    static let appearance = "appearance"
    static let whimsy = "whimsy"
    static let defaultFont = "defaultFont"
    static let todoSort = "todoSort"
    static let doneSinks = "doneSinks"
    static let sidebarMode = "sidebarMode"
    static let tagSort = "tagSort"
    static let stamped = "allClearStamped"
    static let sidebarColumns = "sidebarColumns"
}

/// Whimsy setting (spec section 7). System reduce-motion forces Off.
enum WhimsyLevel: String, CaseIterable, Identifiable {
    case full, subtle, off
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// The effective motion level plus the animations for each moment in the spec's table.
/// Every accessor returns nil when motion is Off, so `withAnimation(nil)` makes the change instant.
struct Motion: Equatable {
    var level: WhimsyLevel

    var isOff: Bool { level == .off }
    var isFull: Bool { level == .full }

    private func pick(_ full: Animation, _ subtle: Animation?) -> Animation? {
        switch level { case .full: return full; case .subtle: return subtle; case .off: return nil }
    }

    /// Old sheet peels away: 680 ms ease-in (Subtle 360 ms).
    var peel: Animation? { pick(.easeIn(duration: 0.68), .easeIn(duration: 0.36)) }
    /// New sheet rises 6 px and fades in, 420 ms after 120 ms.
    var rise: Animation? { pick(.easeOut(duration: 0.42).delay(0.12), .easeOut(duration: 0.3)) }
    /// Paste / insert: falls 16 px, overshoots ~3 px, settles, 280 ms spring.
    var fall: Animation? { pick(.spring(response: 0.28, dampingFraction: 0.55), .spring(response: 0.28, dampingFraction: 0.8)) }
    /// Delete: scale 0.5, rotate 10, drop 14 px, fade, 300 ms ease-in (Subtle: fade 200 ms).
    var delete: Animation? { pick(.easeIn(duration: 0.3), .easeIn(duration: 0.2)) }
    /// Drag lift, 180 ms.
    var lift: Animation? { pick(.spring(response: 0.18, dampingFraction: 0.7), .spring(response: 0.18, dampingFraction: 0.9)) }
    /// Hover a block: lifts 3 px, 180 ms spring. None in Subtle.
    var hover: Animation? { pick(.spring(response: 0.18, dampingFraction: 0.7), nil) }
    /// Menus, popovers, dialogs: scale 0.94 to 1 and fade, 140 ms ease-out (Subtle: fade).
    var popover: Animation? { pick(.easeOut(duration: 0.14), .easeOut(duration: 0.14)) }
    /// Undo toast rising 12 px.
    var toast: Animation? { pick(.spring(response: 0.3, dampingFraction: 0.75), .easeOut(duration: 0.2)) }
    /// To-do count rising 4 px, 360 ms spring.
    var count: Animation? { pick(.spring(response: 0.36, dampingFraction: 0.6), .spring(response: 0.36, dampingFraction: 0.6)) }
    /// Rows reordering.
    var reorder: Animation? { pick(.spring(response: 0.3, dampingFraction: 0.8), .easeOut(duration: 0.2)) }

    /// Removal transition for a deleted block.
    var deleteTransition: AnyTransition {
        switch level {
        case .full: return .asymmetric(insertion: .identity, removal: .modifier(active: DeleteEffect(progress: 1), identity: DeleteEffect(progress: 0)))
        case .subtle: return .asymmetric(insertion: .identity, removal: .opacity)
        case .off: return .identity
        }
    }

    /// Sheet change: old peels up and away from the top-right, new rises 6 px and fades in.
    var sheetTransition: AnyTransition {
        switch level {
        case .off: return .identity
        case .full, .subtle:
            let removal = AnyTransition.modifier(active: PeelEffect(progress: 1), identity: PeelEffect(progress: 0)).combined(with: .opacity)
            let insertion = AnyTransition.modifier(active: RiseEffect(progress: 0), identity: RiseEffect(progress: 1)).combined(with: .opacity)
            return .asymmetric(insertion: insertion.animation(rise), removal: removal)
        }
    }
}

private struct MotionKey: EnvironmentKey { static let defaultValue = Motion(level: .full) }
extension EnvironmentValues {
    var motion: Motion { get { self[MotionKey.self] } set { self[MotionKey.self] = newValue } }
}

/// Runs `change` with the given animation, or instantly when it is nil.
func animate(_ animation: Animation?, _ change: () -> Void) {
    if let animation { withAnimation(animation, change) } else {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t, change)
    }
}

// MARK: Effects

/// Old sheet: translate -60 px, -110 % of its height, rotate -9 degrees about the top-right corner.
struct PeelEffect: GeometryEffect {
    var progress: Double
    var animatableData: Double { get { progress } set { progress = newValue } }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let p = CGFloat(progress)
        let angle: CGFloat = -9 * .pi / 180 * p
        var t = CGAffineTransform(translationX: -60 * p, y: -1.1 * size.height * p)
        // Rotate about the top-right corner.
        t = t.translatedBy(x: size.width, y: 0).rotated(by: angle).translatedBy(x: -size.width, y: 0)
        return ProjectionTransform(t)
    }
}

/// New sheet: rises 6 px into place.
struct RiseEffect: GeometryEffect {
    var progress: Double
    var animatableData: Double { get { progress } set { progress = newValue } }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 0, y: 6 * (1 - CGFloat(progress))))
    }
}

/// Deleted block: scale to 0.5, rotate 10 degrees, drop 14 px, fade.
struct DeleteEffect: ViewModifier {
    var progress: Double
    func body(content: Content) -> some View {
        content
            .scaleEffect(1 - 0.5 * progress)
            .rotationEffect(.degrees(10 * progress))
            .offset(y: 14 * progress)
            .opacity(1 - progress)
    }
}

/// Inserted block: falls 16 px into place; a spring with bounce gives the 3 px overshoot.
struct FallEffect: ViewModifier, Animatable {
    var progress: Double
    var animatableData: Double { get { progress } set { progress = newValue } }
    func body(content: Content) -> some View {
        content.offset(y: -16 * (1 - progress)).opacity(min(1, max(0, progress * 2)))
    }
}

/// Carried row hop: small arc (Full) or a slide (Subtle).
struct HopEffect: ViewModifier, Animatable {
    var progress: Double
    var arc: Bool
    var animatableData: Double { get { progress } set { progress = newValue } }
    func body(content: Content) -> some View {
        content
            .offset(x: 24 * (1 - progress), y: arc ? -10 * sin(progress * .pi) : 0)
            .opacity(progress)
    }
}

/// Scale 0.94 to 1 and fade, for popover and dialog content.
struct PopIn: ViewModifier {
    @Environment(\.motion) private var motion
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(shown || !motion.isFull ? 1 : 0.94)
            .opacity(shown || motion.isOff ? 1 : 0)
            .onAppear { animate(motion.popover) { shown = true } }
    }
}

extension View {
    func popIn() -> some View { modifier(PopIn()) }
}

/// Dotted ripple ring under a freshly pasted block, 520 ms.
struct Ripple: View {
    @Environment(\.palette) private var p
    @State private var t = 0.0
    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .stroke(p.accent, style: StrokeStyle(lineWidth: 1.5, dash: [2, 4]))
            .scaleEffect(1 + 0.12 * t)
            .opacity(1 - t)
            .allowsHitTesting(false)
            .onAppear { withAnimation(.easeOut(duration: 0.52)) { t = 1 } }
    }
}

/// Wiggle values for grips.
struct Wiggle { var angle = 0.0 }

extension View {
    /// Grip wiggle ±12 degrees, 360 ms, each time `trigger` changes.
    func wiggle(trigger: Int) -> some View {
        keyframeAnimator(initialValue: Wiggle(), trigger: trigger) { content, v in
            content.rotationEffect(.degrees(v.angle))
        } keyframes: { _ in
            KeyframeTrack(\.angle) {
                CubicKeyframe(12, duration: 0.09)
                CubicKeyframe(-12, duration: 0.12)
                CubicKeyframe(6, duration: 0.08)
                CubicKeyframe(0, duration: 0.07)
            }
        }
    }
}
