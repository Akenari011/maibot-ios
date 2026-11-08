//
//  AuthStore.swift
//  MaiBot
//
//  Session lifecycle. The panel authenticates with an HttpOnly cookie, so the
//  only way to obtain one from a native app is to run the login flow inside a
//  WKWebView and then harvest the cookie from the shared cookie store.
//
//  Cookies live in the Keychain rather than UserDefaults: they are bearer
//  credentials for the whole panel.
//

import Foundation
import Observation
import Security
import WebKit

enum AuthState: Equatable {
    case unknown
    case loggedOut
    case loggedIn
}

@MainActor
@Observable
final class AuthStore {
    private(set) var state: AuthState = .unknown
    private(set) var lastError: String?

    /// Cookie name prefix is per-instance ("maibot_host_session_<hash>").
    static let cookiePrefix = "maibot_host_session_"

    private let keychainAccount = "maibot.session.cookie"
    private let service = "online.galmaster.maibot"

    // MARK: - Restore on launch

    func restore(client: APIClient) async {
        guard let saved = Keychain.read(service: service, account: keychainAccount),
              !saved.isEmpty else {
            state = .loggedOut
            return
        }
        client.sessionCookie = saved
        do {
            let ok = try await client.checkAuth()
            state = ok ? .loggedIn : .loggedOut
            if !ok { Keychain.delete(service: service, account: keychainAccount) }
        } catch APIError.unauthorized {
            Keychain.delete(service: service, account: keychainAccount)
            state = .loggedOut
        } catch {
            // Network hiccup: keep the cookie, but do not claim to be logged in.
            state = .loggedOut
            lastError = error.localizedDescription
        }
    }

    // MARK: - Harvest from the web view

    /// Called after every navigation in the login web view. Pulls matching
    /// cookies out of the shared store and, if one validates, signs us in.
    func capture(store: WKWebsiteDataStore, client: APIClient) async {
        let cookies = await store.httpCookieStore.allCookies()
        guard let hit = cookies.first(where: { $0.name.hasPrefix(Self.cookiePrefix) }) else {
            return
        }
        let value = "\(hit.name)=\(hit.value)"
        client.sessionCookie = value
        do {
            if try await client.checkAuth() {
                Keychain.write(value, service: service, account: keychainAccount)
                state = .loggedIn
                lastError = nil
            }
        } catch {
            // Not authenticated yet (still on the SSO screen). Stay quiet.
        }
    }

    // MARK: - Sign out

    func signOut(client: APIClient) async {
        try? await client.logout()
        client.sessionCookie = nil
        Keychain.delete(service: service, account: keychainAccount)
        // WKHTTPCookieStore has no bulk clear; delete them one by one.
        let store = WKWebsiteDataStore.default().httpCookieStore
        for cookie in await store.allCookies() {
            await store.delete(cookie)
        }
        state = .loggedOut
    }
}

// MARK: - Keychain

enum Keychain {
    static func write(_ value: String, service: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func read(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
