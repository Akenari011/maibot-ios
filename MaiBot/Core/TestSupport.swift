//
//  TestSupport.swift
//  MaiBot
//
//  Hooks used only by the CI screenshot job. They read launch environment
//  variables, so production builds behave identically when unset.
//

import Foundation

enum TestSupport {
    static var injectedCookie: String? {
        let v = ProcessInfo.processInfo.environment["GM_TEST_COOKIE"] ?? ""
        return v.isEmpty ? nil : v
    }

    static var startTab: String {
        ProcessInfo.processInfo.environment["GM_TEST_TAB"] ?? "home"
    }

    static var forcedTheme: String? {
        let v = ProcessInfo.processInfo.environment["GM_TEST_THEME"] ?? ""
        return v.isEmpty ? nil : v
    }
}