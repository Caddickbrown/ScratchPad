import SwiftUI
import ScratchpadCore

/// Tokens from the Components board, with the dark set from the dark board.
struct Palette {
    var desk: Color, paper: Color, ink: Color, muted: Color, rule: Color, hairline: Color, dot: Color
    var accent: Color, accentInk: Color, overdue: Color, chrome: Color, cell: Color, codeBg: Color, codeInk: Color

    static let light = Palette(
        desk: Color(hex: 0xEDECE7), paper: Color(hex: 0xFBFBF9), ink: Color(hex: 0x1E1E1C), muted: Color(hex: 0x6B6B66),
        rule: Color(hex: 0x8A8A86), hairline: Color(hex: 0xD6D5CF), dot: Color(hex: 0xC4C3BD),
        accent: Color(hex: 0x2E5BDA), accentInk: .white, overdue: Color(hex: 0xC2410C), chrome: Color(hex: 0xF4F3EF),
        cell: .white, codeBg: Color(hex: 0x1E1E1C), codeInk: Color(hex: 0xFBFBF9))

    static let dark = Palette(
        desk: Color(hex: 0x141413), paper: Color(hex: 0x1E1E1C), ink: Color(hex: 0xECEAE4), muted: Color(hex: 0xA3A29C),
        rule: Color(hex: 0x6B6B66), hairline: Color(hex: 0x33332F), dot: Color(hex: 0x3A3A37),
        accent: Color(hex: 0x6E8DF5), accentInk: Color(hex: 0x0B1230), overdue: Color(hex: 0xF08A5B), chrome: Color(hex: 0x1A1A19),
        cell: Color(hex: 0x262624), codeBg: Color(hex: 0x0F0F0E), codeInk: Color(hex: 0xECEAE4))

    static func forScheme(_ scheme: ColorScheme) -> Palette { scheme == .dark ? .dark : .light }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var colorScheme: ColorScheme? { self == .system ? nil : (self == .dark ? .dark : .light) }
}

private struct PaletteKey: EnvironmentKey { static let defaultValue = Palette.light }
extension EnvironmentValues {
    var palette: Palette { get { self[PaletteKey.self] } set { self[PaletteKey.self] = newValue } }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}

enum Fonts {
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: .monospaced) }

    /// Block fonts: Sans = SF, Serif = New York, Mono = SF Mono, Hand = Bradley Hand (with fallbacks).
    static func block(_ family: BlockFont, size: CGFloat, bold: Bool = false, italic: Bool = false) -> Font {
        var font: Font
        switch family {
        case .sans: font = .system(size: size)
        case .serif: font = .system(size: size, design: .serif)
        case .mono: font = .system(size: size, design: .monospaced)
        case .hand: font = hand(size)
        }
        if bold { font = font.bold() }
        if italic { font = font.italic() }
        return font
    }

    static func block(_ b: Block) -> Font { block(b.font, size: CGFloat(b.fontSize), bold: b.bold, italic: b.italic) }

    /// Bradley Hand ships with macOS and iOS; fall back to Noteworthy, then italic New York.
    static func hand(_ size: CGFloat) -> Font {
        for name in handNames where fontExists(name, size) { return .custom(name, size: size) }
        return .system(size: size, design: .serif).italic()
    }

    static let handNames = ["BradleyHandITCTT-Bold", "Noteworthy-Light"]

    static func fontExists(_ name: String, _ size: CGFloat) -> Bool {
        #if os(macOS)
        return NSFont(name: name, size: size) != nil
        #else
        return UIFont(name: name, size: size) != nil
        #endif
    }
}

/// Picks the palette from the resolved color scheme and injects it, along with the effective motion level,
/// so every view reads `@Environment(\.palette)` and `@Environment(\.motion)`.
struct Themed<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SettingsKey.whimsy) private var whimsy: WhimsyLevel = .full
    let content: () -> Content

    var body: some View {
        let motion = Motion(level: reduceMotion ? .off : whimsy)
        content()
            .environment(\.palette, Palette.forScheme(scheme))
            .environment(\.motion, motion)
            .animation(motion.isOff ? nil : .easeInOut(duration: 0.36), value: scheme)
    }
}
