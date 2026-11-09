import SwiftUI

struct ChatManagementView: View {
    @Environment(APIClient.self) private var client
    @Environment(AuthStore.self) private var auth
    @Environment(\.palette) private var p
    @State private var sessions: [ChatStream] = []
    @State private var query = ""
    @State private var error: String?
    @State private var loading = false
    @State private var selected: ChatStream?
    @State private var detail: [String: Any]?
    @State private var detailLoading = false
    @State private var paused = false
    @State private var ruleTime = "*"
    @State private var ruleValue = "0.5"
    @State private var savingRule = false

    private var filtered: [ChatStream] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? sessions : sessions.filter { $0.displayName.lowercased().contains(q) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundStyle(p.textSecondary)
                    TextField("搜索会话…", text: $query).font(.system(size: 14)).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                .padding(.horizontal, 12).frame(height: 38).background(p.iconCircle, in: RoundedRectangle(cornerRadius: 10))
                if let e = error { ErrorBanner(message: e) { Task { await load() } } }
                Text("会话（\(filtered.count)）").font(.system(size: 12)).foregroundStyle(p.textSecondary)
                ForEach(filtered) { s in
                    Button { Task { await open(s) } } label: {
                        Panel(padding: 14) {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(s.displayName).font(.system(size: 14, weight: .semibold)).foregroundStyle(p.text).lineLimit(1)
                                    Text(s.chatType == "private" ? "私聊" : "群聊").font(.system(size: 11)).foregroundStyle(p.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(p.textTertiary)
                            }
                        }
                    }.buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .background(p.bg)
        .navigationTitle("聊天管理")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .sheet(item: $selected) { s in detailSheet(s) }
    }

    private func detailSheet(_ s: ChatStream) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if detailLoading { ProgressView() }
                    Text(s.displayName).font(.system(size: 20, weight: .bold)).foregroundStyle(p.text)
                    if let d = detail {
                        if let pr = d["private_reply"] as? [String: Any] {
                            Panel(padding: 14) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("暂停回复").font(.system(size: 14, weight: .semibold)).foregroundStyle(p.text)
                                        Text("当前：\(paused ? "已暂停" : "正常")" + ((pr["global_paused"] as? Bool) == true ? "（全局已暂停）" : ""))
                                            .font(.system(size: 11)).foregroundStyle(p.textSecondary)
                                    }
                                    Spacer()
                                    Toggle("", isOn: Binding(get: { paused }, set: { v in Task { await setPause(s, v) } }))
                                        .labelsHidden()
                                        .disabled(s.chatType != "private")
                                }
                            }
                        }
                        if let tf = d["talk_frequency"] as? [String: Any] {
                            Panel(padding: 14) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("发言频率").font(.system(size: 14, weight: .semibold)).foregroundStyle(p.text)
                                    Text((tf["effective_value_label"] as? String) ?? "—")
                                        .font(.system(size: 12)).foregroundStyle(p.textSecondary)
                                    Text("当前时段 \((tf["current_time"] as? String) ?? "")")
                                        .font(.system(size: 11)).foregroundStyle(p.textTertiary)
                                    Divider().padding(.vertical, 4)
                                    HStack(spacing: 8) {
                                        TextField("* 或 HH:MM", text: $ruleTime)
                                            .font(.system(size: 12, design: .monospaced))
                                            .padding(6).background(p.iconCircle, in: RoundedRectangle(cornerRadius: 6))
                                        TextField("0-1", text: $ruleValue)
                                            .font(.system(size: 12, design: .monospaced)).keyboardType(.decimalPad)
                                            .padding(6).background(p.iconCircle, in: RoundedRectangle(cornerRadius: 6)).frame(width: 70)
                                    }
                                    HStack(spacing: 8) {
                                        Button(savingRule ? "保存中…" : "保存规则") { Task { await saveRule(s) } }
                                            .font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
                                            .padding(.horizontal, 12).padding(.vertical, 6).background(p.orange, in: Capsule())
                                        Button("删除该时段") { Task { await deleteRule(s) } }
                                            .font(.system(size: 12, weight: .medium)).foregroundStyle(.red)
                                            .padding(.horizontal, 12).padding(.vertical, 6).background(Color.red.opacity(0.1), in: Capsule())
                                    }.disabled(savingRule)
                                }
                            }
                        }
                    }
                    Spacer(minLength: 40)
                }
                .padding(16)
            }
            .background(p.bg)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { selected = nil } } }
        }
    }

    private func saveRule(_ s: ChatStream) async {
        savingRule = true; defer { savingRule = false }
        do {
            let mode = try await client.hostMode()
            guard let id = mode.selectedBotID else { return }
            let v = Double(ruleValue) ?? 0.5
            _ = try await client.setTalkFrequency(botID: id, sessionID: s.sessionID, previousTime: nil, time: ruleTime, value: v)
            await open(s)
        } catch { self.error = error.localizedDescription }
    }

    private func deleteRule(_ s: ChatStream) async {
        savingRule = true; defer { savingRule = false }
        do {
            let mode = try await client.hostMode()
            guard let id = mode.selectedBotID else { return }
            _ = try await client.deleteTalkFrequency(botID: id, sessionID: s.sessionID, time: ruleTime)
            await open(s)
        } catch { self.error = error.localizedDescription }
    }

    private func open(_ s: ChatStream) async {
        selected = s; detail = nil; detailLoading = true
        defer { detailLoading = false }
        do {
            let mode = try await client.hostMode()
            guard let id = mode.selectedBotID else { return }
            let raw = try await client.chatSessionDetail(botID: id, sessionID: s.sessionID)
            let d = (raw as? [String: Any])?["detail"] as? [String: Any] ?? [:]
            detail = d
            paused = ((d["private_reply"] as? [String: Any])?["paused"] as? Bool) ?? false
        } catch { self.error = error.localizedDescription }
    }

    private func setPause(_ s: ChatStream, _ v: Bool) async {
        do {
            let mode = try await client.hostMode()
            guard let id = mode.selectedBotID else { return }
            _ = try await client.setPrivateReplyPause(botID: id, sessionID: s.sessionID, paused: v)
            paused = v
        } catch { self.error = error.localizedDescription }
    }

    private func load() async {
        loading = true; defer { loading = false }
        do {
            let mode = try await client.hostMode()
            guard let id = mode.selectedBotID else { return }
            sessions = try await client.chatStreams(botID: id)
            error = nil
        } catch APIError.unauthorized { await auth.signOut(client: client) }
        catch { self.error = error.localizedDescription }
    }
}
