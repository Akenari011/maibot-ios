//
//  Theme.swift
//  MaiBot
//
//  Colour tokens lifted from the web dashboard's CSS variables, plus the
//  Liquid Glass surface used throughout the chrome.
//

import SwiftUI

// MARK: - Palette

struct Palette {
    let background: Color
    let surface: Color
    let surfaceRaised: Color
    let border: Color
    let text: Color
    let textDim: Color
    let textMute: Color
    let accent: Color
    let amber: Color
    let danger: Color
    let info: Color
    let violet: Color
    let isDark: Bool

    /// --color-background: 222.2 84% 4.9% / card: 188.5 18% 8.8%
    static let midnight = Palette(
        background: Color(hex: 0x0B1013),
        surface: Color(hex: 0x121A1D),
        surfaceRaised: Color(hex: 0x182326),
        border: Color(hex: 0x1F2C30),
        text: Color(hex: 0xE8EDEF),
        textDim: Color(hex: 0x93A5AB),
        textMute: Color(hex: 0x607076),
        accent: Color(hex: 0x00BB7F),
        amber: Color(hex: 0xF99C00),
        danger: Color(hex: 0xFF3B30),
        info: Color(hex: 0x00A5EF),
        violet: Color(hex: 0x8D54FF),
        isDark: true
    )

    /// Retro paper: --retro-paper / --retro-ink / --retro-rust / --retro-gold
    static let paper = Palette(
        background: Color(hex: 0xE7DCC3),
        surface: Color(hex: 0xF1E9D6),
        surfaceRaised: Color(hex: 0xFAF4E5),
        border: Color(hex: 0xC9B896),
        text: Color(hex: 0x0A4550),
        textDim: Color(hex: 0x4A6E74),
        textMute: Color(hex: 0x8A9A93),
        accent: Color(hex: 0xC04D27),
        amber: Color(hex: 0x9F8450),
        danger: Color(hex: 0x913A1D),
        info: Color(hex: 0x0D6170),
        violet: Color(hex: 0x8D54FF),
        isDark: false
    )
}

// MARK: - Theme preference

enum ThemePreference: String, CaseIterable, Identifiable {
    case system, midnight, paper
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:   return "跟随系统"
        case .midnight: return "深色"
        case .paper:    return "复古纸张"
        }
    }

    var symbol: String {
        switch self {
        case .system:   return "circle.lefthalf.filled"
        case .midnight: return "moon.stars"
        case .paper:    return "doc.text"
        }
    }
}

// MARK: - Environment

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette.midnight
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8)  & 0xFF) / 255,
            blue:  Double( hex        & 0xFF) / 255,
            opacity: alpha
        )
    }
}

// MARK: - Surfaces

/// Standard card. On the dark theme it is a Liquid Glass slab so content
/// refracts behind it; the paper theme stays opaque because glass over a
/// paper texture reads as dirt rather than depth.
struct Panel<Content: View>: View {
    @Environment(\.palette) private var p
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        let base = content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)

        if p.isDark {
            base
                .glassEffect(.regular.tint(p.accent.opacity(0.06)), in: shape)
                .overlay { shape.strokeBorder(p.border.opacity(0.7), lineWidth: 1) }
        } else {
            base
                .background(p.surface, in: shape)
                .overlay { shape.strokeBorder(p.border, lineWidth: 1) }
                .shadow(color: p.text.opacity(0.05), radius: 2, y: 1)
        }
    }
}

/// Small status pill ("运行中" / "已停止") with a breathing dot.
struct StatusPill: View {
    @Environment(\.palette) private var p
    let text: String
    let tone: Tone

    enum Tone { case ok, warn, bad, idle }

    private var color: Color {
        switch tone {
        case .ok:   return p.accent
        case .warn: return p.amber
        case .bad:  return p.danger
        case .idle: return p.textMute
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .opacity(0.9)
            Text(text).font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(color.opacity(0.12), in: .capsule)
    }
}
