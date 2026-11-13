import AppIntents
import SwiftUI

/// アプリの設定画面のプレビューで、ウィジェットのボタンを押したときの動き。
/// 本物のウィジェットでは nil で、ボタンは AppIntent で動く(プレビューで AppIntent を動かすと、本物のウィジェットの表示が変わってしまう)
struct WidgetPreviewActions {
    /// 前へ(-1)・次へ(1)
    var step: (Int) -> Void
    /// 「今日へ」「今週へ」
    var reset: () -> Void
    /// 右上のカレンダーの切り替え
    var cycle: () -> Void
}

private struct WidgetPreviewActionsKey: EnvironmentKey {
    static let defaultValue: WidgetPreviewActions? = nil
}

extension EnvironmentValues {
    var widgetPreviewActions: WidgetPreviewActions? {
        get { self[WidgetPreviewActionsKey.self] }
        set { self[WidgetPreviewActionsKey.self] = newValue }
    }
}

/// ウィジェットのボタン。ウィジェットでは AppIntent、設定画面のプレビューでは、その場の動き
struct WidgetActionButton<Intent: AppIntent, Label: View>: View {
    @Environment(\.widgetPreviewActions) private var preview
    let intent: Intent
    let previewAction: (WidgetPreviewActions) -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        if let preview {
            Button { previewAction(preview) } label: { label() }
                .buttonStyle(.plain)
        } else {
            Button(intent: intent) { label() }
                .buttonStyle(.plain)
        }
    }
}

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
    /// 右下に重ねる、切り替えの印の丸の大きさ
    var badge: CGFloat = 11

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            avatar
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: badge * 0.6, weight: .heavy))
                .foregroundStyle(.primary)
                .frame(width: badge, height: badge)
                .background(Circle().fill(Color(.systemBackground)))
                .offset(x: 3, y: 3)
        }
        .frame(width: size, height: size)
        .padding(.trailing, 2)
        .accessibilityLabel("カレンダーを切り替え")
    }

    @ViewBuilder
    private var avatar: some View {
        if sw.icon == nil, let me = sw.me {
            // 自分のカレンダーは、自分のプロフィールのアイコン
            WidgetOwnerAvatar(owner: me, size: size)
        } else if let icon = sw.icon, let photo = AvatarStyle.photo(from: icon) {
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
