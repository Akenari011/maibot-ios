//
//  ChatListView.swift
//  MaiBot
//
//  聊天 tab 第一态：会话列表（网页版 routes/chat/MobileChat.tsx）。
//  大标题「聊天」+ 搜索「搜索聊天流…」+ 我的会话（本地，点进对话）+ 观察的聊天流。
//

import SwiftUI

struct ChatListView: View {
    @Environment(APIClient.self) private var client
    @Environment(\.palette) private var p
    @State private var streams: [ChatStream] = []
    @State private var search = ""
    @State private var loading = false
    @State private var error: String?

    private var filtered: [ChatStream] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? streams : streams.filter { $0.displayName.lowercased().contains(q) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("聊天").font(.system(size: 34, weight: .bold)).tracking(-0.4).foregroundStyle(p.text)
                searchField
                if loading { ProgressView().frame(maxWidth: .infinity).padding(.top, 8) }
                if let error { Text(error).font(.system(size: 12)).foregroundStyle(.red) }

                section("我的会话") {
                    NavigationLink { ChatView() } label: {
                        ChatRowView(icon: "bubble.left.and.bubble.right.fill", title: "与麦麦聊天",
                                    subtitle: "本地聊天室 · 在线", time: "", online: true, avatarTint: p.text)
                    }.buttonStyle(PressableStyle())
                }

                if !filtered.isEmpty {
                    section("麦麦的聊天流") {
                        ForEach(filtered) { s in
                            NavigationLink { ChatView() } label: {
                                ChatRowView(icon: "person.2.fill", title: s.displayName,
                                            subtitle: s.subtitle, time: s.timeText, online: false, avatarTint: p.textSecondary)
                            }.buttonStyle(PressableStyle())
                            if s.id != filtered.last?.id { rowDivider }
                        }
                    }
                }

                Spacer(minLength: 90)
            }
            .padding(.horizontal, 16).padding(.top, 8)
        }
        .background(p.bg)
        .task { await load() }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 16)).foregroundStyle(p.textSecondary)
            TextField("搜索聊天流…", text: $search)
                .font(.system(size: 15)).textInputAutocapitalization(.never).autocorrectionDisabled()
        }
        .padding(.horizontal, 14).frame(height: 40)
        .background(p.iconCircle, in: RoundedRectangle(cornerRadius: 12))
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13)).foregroundStyle(p.textSecondary).padding(.leading, 4)
            VStack(spacing: 0) { content() }
                .background(p.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private var rowDivider: some View {
        Rectangle().fill(p.separator).frame(height: 1).padding(.leading, 76)
    }

    private func load() async {
        loading = true; defer { loading = false }
        do {
            let mode = try await client.hostMode()
            if let id = mode.selectedBotID {
                streams = (try? await client.chatStreams(botID: id)) ?? []
            }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

struct ChatRowView: View {
    @Environment(\.palette) private var p
    let icon: String
    let title: String
    let subtitle: String
    let time: String
    let online: Bool
    let avatarTint: Color

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Circle().fill(p.iconCircle).frame(width: 50, height: 50)
                    .overlay { Image(systemName: icon).font(.system(size: 20)).foregroundStyle(avatarTint) }
                if online {
                    Circle().fill(p.green).frame(width: 12, height: 12)
                        .overlay { Circle().strokeBorder(p.card, lineWidth: 2) }
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(p.text).lineLimit(1)
                Text(subtitle).font(.system(size: 15)).foregroundStyle(p.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if !time.isEmpty { Text(time).font(.system(size: 13)).foregroundStyle(p.textSecondary) }
        }
        .padding(.horizontal, 16).frame(height: 76)
        .contentShape(.rect)
    }
}
