import SwiftUI

struct SettingsComponentsView: View {
    @Environment(\.palette) private var p
    @State private var toggle = true
    @State private var text = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                section("颜色") {
                    HStack(spacing: 10) {
                        swatch("背景", p.bg)
                        swatch("卡片", p.card)
                        swatch("强调", p.orange)
                        swatch("成功", p.green)
                        swatch("填充", p.iconCircle)
                    }
                }
                section("按钮") {
                    HStack(spacing: 10) {
                        Text("主要").font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                            .padding(.horizontal, 16).padding(.vertical, 10).background(p.orange, in: Capsule())
                        Text("次要").font(.system(size: 14, weight: .medium)).foregroundStyle(p.orange)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .overlay { Capsule().strokeBorder(p.orange, lineWidth: 1.5) }
                    }
                }
                section("控件") {
                    Toggle("开关示例", isOn: $toggle).tint(p.orange)
                    TextField("输入框示例", text: $text)
                        .font(.system(size: 14)).padding(10)
                        .background(p.card, in: RoundedRectangle(cornerRadius: 10))
                        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(p.separator) }
                }
                section("排版") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("大标题 Title").font(.system(size: 28, weight: .bold)).foregroundStyle(p.text)
                        Text("小标题 Headline").font(.system(size: 17, weight: .semibold)).foregroundStyle(p.text)
                        Text("正文 Body 示例文本").font(.system(size: 15)).foregroundStyle(p.text)
                        Text("辅助说明 Secondary").font(.system(size: 12)).foregroundStyle(p.textSecondary)
                    }
                }
                section("面板") {
                    Panel { Text("Panel 卡片容器").font(.system(size: 14)).foregroundStyle(p.text) }
                }
            }
            .padding(16)
        }
        .background(p.bg)
        .pageChrome("设置组件")
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12)).foregroundStyle(p.textSecondary)
            content()
        }
    }

    private func swatch(_ label: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 8).fill(color).frame(height: 40)
                .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(p.separator) }
            Text(label).font(.system(size: 10)).foregroundStyle(p.textTertiary)
        }
    }
}
