import SwiftUI

/// 前へ・次へなどの小さな丸ボタン
struct WidgetStepButtonLabel: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.primary)
            .frame(width: 26, height: 22)
            .background(Capsule().fill(Color(.secondarySystemFill)))
    }
}

/// 「今日へ」「今週へ」の紫のボタン
struct WidgetBackLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.app(10.5, weight: .semibold))
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(Capsule().fill(Theme.accent))
    }
}

/// 右上のカレンダー切り替えボタン。いま見ているカレンダーのアイコン(丸)に、切り替えの印を右下に重ねる。
/// 自分のカレンダーは、アクセント色の丸にカレンダーの記号
struct WidgetCalendarSwitchLabel: View {
    let sw: WidgetCalendarSwitch
    var size: CGFloat = 20

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            avatar
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 6.5, weight: .heavy))
                .foregroundStyle(.primary)
                .frame(width: 11, height: 11)
                .background(Circle().fill(Color(.systemBackground)))
                .offset(x: 3, y: 3)
        }
        .frame(width: size, height: size)
        .padding(.trailing, 2)
        .accessibilityLabel("カレンダーを切り替え")
    }

    @ViewBuilder
    private var avatar: some View {
        if let icon = sw.icon, let photo = AvatarStyle.photo(from: icon) {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            // 共有カレンダーの記号には色("名前|#rrggbb")が付いていることがある。無ければアクセント色の丸
            let parts = (sw.icon ?? "calendar").components(separatedBy: "|")
            let fill = parts.count > 1 && parts[1].hasPrefix("#") ? Color(hex: parts[1]) : Theme.accent
            Image(systemName: parts.first ?? "calendar")
                .font(.system(size: size * 0.48, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: size, height: size)
                .background(Circle().fill(fill))
        }
    }
}
