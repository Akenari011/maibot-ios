//
//  Motion.swift
//  MaiBot
//
//  Animation constants transcribed from the web dashboard's motion usage
//  (motion/react v12 + @react-spring + tailwind animate-*). Every custom
//  .animation in the app should reference these so the feel matches the web.
//  Respect reduce-motion at the call site with @Environment(\.accessibilityReduceMotion).
//

import SwiftUI

enum Motion {
    // Durations (seconds)
    static let fast: Double = 0.12
    static let medium: Double = 0.2
    static let page: Double = 0.26

    // Bottom tab switch / active pill (web spring stiffness 420 damping 36 mass .8)
    static var tab: Animation { .interpolatingSpring(stiffness: 420, damping: 36) }
    // Icon pop on tap (scale .25s cubic-bezier(.34,1.56,.64,1))
    static var iconPop: Animation { .spring(response: 0.25, dampingFraction: 0.55) }
    // List row / header spring (360/30/0.75)
    static var row: Animation { .spring(response: 0.35, dampingFraction: 0.7) }
    // Swipe row (420/38/0.8)
    static var swipe: Animation { .spring(response: 0.35, dampingFraction: 0.72) }
    // Chat bubble insertion (360/30/0.75)
    static var bubble: Animation { .spring(response: 0.35, dampingFraction: 0.8) }
    // Page transition list<->conversation: 0.26s cubic-bezier(.22,1,.36,1)
    static var pageTransition: Animation { .timingCurve(0.22, 1, 0.36, 1, duration: 0.26) }
    // Sheet / dialog / overlay fade
    static var overlay: Animation { .easeOut(duration: 0.2) }
    // Accordion / disclosure
    static var accordion: Animation { .easeInOut(duration: 0.2) }
    // Button press feedback
    static var press: Animation { .easeOut(duration: 0.12) }

    /// Returns the animation unless reduce-motion is on.
    static func respecting(_ reduce: Bool, _ animation: Animation) -> Animation? {
        reduce ? nil : animation
    }
}
