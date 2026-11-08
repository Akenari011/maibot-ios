//
//  Theme.swift
//  MaiBot
//
//  Design tokens taken directly off the panel: warm off-white canvas, pure
//  white cards, black display type, green for "alive", orange for accents.
//

import SwiftUI

// MARK: - Palette

struct Palette {
    let bg: Color
    let card: Color
    let text: Color
    let textSecondary: Color
    let textTertiary: Color
    let separator: Color
    let green: Color
    let orange: Color
    let iconCircle: Color
    let progressTrack: Color
    let progressFill: Color

    static let panel = Palette(
        bg: Color(hex: 0xF5F3EE),
        card: Color(hex: 0xFFFFFF),
        text: Color(hex: 0x1C1C1E),
        textSecondary: Color(hex: 0x8A8A8E),
        textTertiary: Color(hex: 0xB2B0AB),
        separator: Color(hex: 0xEFEDE8),
        green: Color(hex: 0x22C55E),
        orange: Color(hex: 0xE8862C),
        iconCircle: Color(hex: 0xF0EEE9),
        progressTrack: Color(hex: 0xF7DCC4),
        progressFill: Color(hex: 0x1C1C1E)
    )
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette.panel
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

// MARK: - Card

struct Panel<Content: View>: View {
    @Environment(\.palette) private var p
    var padding: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(p.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(p.separator, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.03), radius: 6, y: 2)
    }
}

// MARK: - Small pieces

/// Green (or orange) dot + label, used under the activity card.
struct DotTag: View {
    @Environment(\.palette) private var p
    let text: String
    var color: Color? = nil

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color ?? p.green).frame(width: 9, height: 9)
            Text(text).font(.system(size: 15)).foregroundStyle(p.text)
        }
    }
}

/// Circular icon cell from the quick-action grid.
struct GridTile: View {
    @Environment(\.palette) private var p
    let icon: String
    let label: String
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    Circle().fill(p.iconCircle).frame(width: 56, height: 56)
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(p.text)
                }
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(p.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

/// One storage row: label, value, percent, and the orange/black bar.
struct StorageRow: View {
    @Environment(\.palette) private var p
    let label: String
    let value: String
    let fraction: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(.system(size: 16, weight: .semibold)).foregroundStyle(p.text)
                Text(value).font(.system(size: 16, weight: .semibold)).foregroundStyle(p.text)
                Spacer()
                Text(String(format: "%.0f%%", fraction * 100))
                    .font(.system(size: 15))
                    .foregroundStyle(p.textSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(p.progressTrack)
                    Capsule().fill(p.progressFill)
                        .frame(width: max(6, geo.size.width * min(max(fraction, 0), 1)))
                }
            }
            .frame(height: 9)
        }
    }
}

/// Compact "24小时 / 7天" segmented chips.
struct SegmentedChips<Item: Hashable>: View {
    @Environment(\.palette) private var p
    let items: [Item]
    let label: (Item) -> String
    @Binding var selection: Item

    var body: some View {
        HStack(spacing: 6) {
            ForEach(items, id: \.self) { item in
                let on = item == selection
                Button {
                    selection = item
                } label: {
                    Text(label(item))
                        .font(.system(size: 13, weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? p.text : p.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(on ? p.iconCircle : Color.clear, in: .capsule)
                }
                .buttonStyle(.plain)
            }
        }
    }
}