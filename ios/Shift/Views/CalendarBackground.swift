import SwiftUI
import UIKit

/// カレンダーの背景色。ライトとダークで別の色を持ち、ダークは自動で暗い色になる
enum CalendarBackground {
    struct Option: Identifiable {
        let key: String
        let name: String
        let light: String
        let dark: String
        var id: String { key }
    }

    /// 自分のカレンダーの背景(共有カレンダーは、共有カレンダーごとに別で持つ)
    static let personalKey = "calendarBackground"

    /// 色は、白(ダークは標準の暗い色)を多めに混ぜた、ごく薄い色
    static let options: [Option] = [
        Option(key: "", name: "標準", light: "#ffffff", dark: "#1c1c1e"),
        Option(key: "cream", name: "クリーム", light: "#fffcf6", dark: "#22211c"),
        Option(key: "sakura", name: "さくら", light: "#fef8f9", dark: "#251f22"),
        Option(key: "peach", name: "ピーチ", light: "#fff9f4", dark: "#25201c"),
        Option(key: "lemon", name: "レモン", light: "#fffceb", dark: "#24221b"),
        Option(key: "mint", name: "ミント", light: "#f5fcf6", dark: "#1b251f"),
        Option(key: "blue", name: "あお", light: "#f5fafe", dark: "#1b222a"),
        Option(key: "aqua", name: "みずいろ", light: "#f3faf9", dark: "#1a2524"),
        Option(key: "lavender", name: "ラベンダー", light: "#f8f5fe", dark: "#211e2a"),
        Option(key: "lilac", name: "ライラック", light: "#fbf6fc", dark: "#251f2a"),
        Option(key: "gray", name: "ライトグレー", light: "#f7f8fa", dark: "#25262a"),
        Option(key: "beige", name: "ベージュ", light: "#faf8f3", dark: "#24211b"),
    ]

    static func option(_ key: String) -> Option? { options.first { $0.key == key } }

    static func name(_ key: String) -> String { option(key)?.name ?? "標準" }

    /// 背景の色。空や知らない名前は標準(システムの背景)
    static func color(_ key: String) -> Color {
        guard !key.isEmpty, let o = option(key) else { return Color(.systemBackground) }
        return Color(UIColor { trait in
            UIColor(Color(hex: trait.userInterfaceStyle == .dark ? o.dark : o.light))
        })
    }
}

private struct CalendarBackgroundKey: EnvironmentKey { static let defaultValue = Color(.systemBackground) }

extension EnvironmentValues {
    /// いま表示しているカレンダーの背景色(予定バーの下地もこれに合わせる)
    var calendarBackground: Color {
        get { self[CalendarBackgroundKey.self] }
        set { self[CalendarBackgroundKey.self] = newValue }
    }
}

/// カレンダー背景を、実際のカレンダーを見ながら選ぶ(カレンダーは操作できない。下に候補を横スクロールで並べる)
struct CalendarBackgroundSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Store.self) private var envStore
    @AppStorage("startMonday") private var startMonday = false
    let title: String
    @Binding var selection: String
    /// プレビューに出す予定の入れ物。共有カレンダーでは、その共有カレンダーの中身(nil なら、自分のカレンダー)
    var previewStore: Store? = nil

    var body: some View {
        let bg = CalendarBackground.color(selection)
        NavigationStack {
            VStack(spacing: 0) {
                Divider()
                MonthView(anchor: Rules.today(), startMonday: startMonday, summaryOn: false, selectedDate: nil,
                          onSelectDay: { _ in }, onSelectEvent: { _ in }, onTapEvent: { _, _ in }, onDropEvent: { _, _ in },
                          onSelectPayday: { _ in }, onLongPressDay: { _ in })
                    .environment(previewStore ?? envStore)
                    .environment(\.calendarBackground, bg)
                    .background(bg)
                    .allowsHitTesting(false)
                    .frame(maxHeight: .infinity)
                Divider()
                picker
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } } }
        }
    }

    private var picker: some View {
        VStack(spacing: 8) {
            HStack {
                Text("背景色").font(.app(14))
                Text(CalendarBackground.name(selection))
                    .font(.app(14, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Spacer()
                Button("標準に戻す") { selection = "" }
                    .font(.app(13))
                    .disabled(selection.isEmpty)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(CalendarBackground.options) { o in swatch(o) }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func swatch(_ o: CalendarBackground.Option) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12)
        return Button { selection = o.key } label: {
            shape.fill(CalendarBackground.color(o.key))
                .frame(width: 54, height: 72)
                .overlay(shape.stroke(Color(.separator), lineWidth: 1))
                .overlay(shape.stroke(Theme.accent, lineWidth: 3).padding(-3).opacity(selection == o.key ? 1 : 0))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(o.name)
    }
}
