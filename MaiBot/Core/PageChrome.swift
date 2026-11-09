import SwiftUI

/// 手机端统一的二级/三级页面页头：左上角 44pt 圆形玻璃返回按钮 + 34pt 大标题。
/// 对齐网页版 MobilePageHeader：h-11 w-11 rounded-full glass + text-[34px] font-bold。
struct PageChromeModifier: ViewModifier {
    let title: String
    var showsTitle: Bool = true
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var p

    func body(content: Content) -> some View {
        content
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 22, weight: .regular))
                            .foregroundStyle(p.text)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay { Circle().strokeBorder(Color.white.opacity(0.55), lineWidth: 0.5) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("返回")
                    if showsTitle {
                        Text(title)
                            .font(.system(size: 34, weight: .bold))
                            .tracking(-0.4)
                            .foregroundStyle(p.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 2)
                .padding(.bottom, 6)
                .background(p.bg)
            }
    }
}

extension View {
    func pageChrome(_ title: String, showsTitle: Bool = true) -> some View {
        modifier(PageChromeModifier(title: title, showsTitle: showsTitle))
    }
}
