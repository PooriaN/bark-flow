import SwiftUI

/// Appearance is deliberately independent of recording, model choice and insertion.
/// Stable identifiers keep saved preferences compatible when themes are reordered.
enum FlowTheme: String, CaseIterable, Identifiable {
    case minimal, breakwater, downstroke, drawnWake, heartwood
    var id: String { rawValue }
    static let preferenceKey = "appearance.theme.v1"
    static func saved(in defaults: UserDefaults = .standard) -> Self {
        defaults.string(forKey: preferenceKey).flatMap(Self.init(rawValue:)) ?? .minimal
    }
    func save(in defaults: UserDefaults = .standard) { defaults.set(rawValue, forKey: Self.preferenceKey) }
    var name: String {
        switch self {
        case .minimal: "Minimal Wave"
        case .breakwater: "Breakwater"
        case .downstroke: "Downstroke"
        case .drawnWake: "Drawn Wake"
        case .heartwood: "Heartwood"
        }
    }
    var detail: String {
        switch self {
        case .minimal: "A short, quiet wave. Only what you need."
        case .breakwater: "A warm lacquer edge that rises with your voice."
        case .downstroke: "Ivory paper. Your voice, drawn in ink."
        case .drawnWake: "A cobalt thread suspended in sea glass."
        case .heartwood: "Engraved amber rings on smoked umber."
        }
    }
    var hudSize: CGSize {
        switch self {
        case .minimal: CGSize(width: 288, height: 76)
        case .breakwater: CGSize(width: 320, height: 88)
        case .downstroke: CGSize(width: 304, height: 76)
        case .drawnWake: CGSize(width: 320, height: 80)
        case .heartwood: CGSize(width: 156, height: 164)
        }
    }
    var dark: Bool { self == .breakwater || self == .heartwood }
    var ink: Color { dark ? Color(hex:0xEFE6D6) : Color(hex:self == .downstroke ? 0x302E29 : 0x173B34) }
    var surface: Color {
        switch self {
        case .minimal: Color(hex:0xF2F5F2)
        case .breakwater: Color(hex:0x211B17)
        case .downstroke: Color(hex:0xEFE8D8)
        case .drawnWake: Color(hex:0xDCE8E2)
        case .heartwood: Color(hex:0x17110D)
        }
    }
    var accent: Color {
        switch self {
        case .minimal: Color(hex:0x315C51)
        case .breakwater, .heartwood: Color(hex:0xF2B86C)
        case .downstroke: Color(hex:0x39352D)
        case .drawnWake: Color(hex:0x244FC4)
        }
    }
    var editor: Color { dark ? Color(hex:0x2D2520) : Color.white.opacity(0.65) }
    var displayFont: Font {
        switch self {
        case .heartwood: .custom("Optima", size:26)
        case .downstroke: .system(size:26, design:.serif)
        case .drawnWake: .custom("Avenir Next", size:24)
        default: .system(size:24, weight:.semibold)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red:Double((hex >> 16) & 255)/255,
                  green:Double((hex >> 8) & 255)/255, blue:Double(hex & 255)/255, opacity:1)
    }
}

/// Continuous exponential envelope. Its state is bounded and is never on the audio thread.
struct VoiceEnvelope {
    private(set) var origin = 0.0
    private(set) var target = 0.0
    private(set) var changedAt = 0.0
    static func normalized(_ raw: Double) -> Double {
        guard raw.isFinite else { return 0 }
        return min(1, max(0, (raw - 0.025) / 0.975))
    }
    func value(at time: Double) -> Double {
        let tau = target > origin ? 0.035 : 0.22
        return target + (origin - target) * exp(-max(0, time-changedAt)/tau)
    }
    mutating func receive(_ raw: Double, at time: Double) {
        origin = value(at:time); target = Self.normalized(raw); changedAt = time
    }
}
