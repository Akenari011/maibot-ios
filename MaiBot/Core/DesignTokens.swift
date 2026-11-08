//
//  DesignTokens.swift
//  MaiBot
//
//  Exact design tokens read from the web dashboard (dashboard/src/index.css
//  and lib/theme/tokens.ts, light "modern" skin). Use these for pixel fidelity
//  in new/refactored screens. Existing screens may keep Palette.panel for now.
//

import SwiftUI

enum WebColor {
    static let primary = Color(hex: 0xE06F06)          // hsl(28.9 94.8% 45.1%)
    static let primaryFg = Color(hex: 0xF8FAFC)
    static let background = Color(hex: 0xFFFFFF)
    static let foreground = Color(hex: 0x020817)
    static let card = Color(hex: 0xFBFCFC)
    static let muted = Color(hex: 0xF4F6F6)
    static let mutedFg = Color(hex: 0x608990)
    static let secondary = Color(hex: 0xF1F7F8)
    static let border = Color(hex: 0xE5ECED)
    static let accent = Color(hex: 0x55AB49)           // green
    static let destructive = Color(hex: 0xEF4444)

    // Dark palette (defaultDarkTokens)
    static let dBg = Color(hex: 0x020817)
    static let dCard = Color(hex: 0x12191A)
    static let dPopover = Color(hex: 0x151E20)
    static let dFg = Color(hex: 0xF8FAFC)
    static let dMuted = Color(hex: 0x273032)
    static let dMutedFg = Color(hex: 0x94B3B8)
    static let dBorder = Color(hex: 0x243336)
}

enum Radius {
    static let sm: CGFloat = 4
    static let md: CGFloat = 6
    static let lg: CGFloat = 8
    static let xl: CGFloat = 12
    static let sheet: CGFloat = 28
    static let group: CGFloat = 24   // manage group cards rounded-3xl
}

enum Spacing {
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
}

enum ControlHeight {
    static let xs: CGFloat = 28
    static let sm: CGFloat = 32
    static let regular: CGFloat = 36
    static let lg: CGFloat = 44
}
