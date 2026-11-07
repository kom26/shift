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

    static let options: [Option] = [
        Option(key: "", name: "標準", light: "#ffffff", dark: "#1c1c1e"),
        Option(key: "cream", name: "クリーム", light: "#fffbf1", dark: "#26231b"),
        Option(key: "sakura", name: "さくら", light: "#fef4f6", dark: "#2a2024"),
        Option(key: "peach", name: "ピーチ", light: "#fff6ee", dark: "#2a221b"),
        Option(key: "lemon", name: "レモン", light: "#fffbe0", dark: "#282619"),
        Option(key: "mint", name: "ミント", light: "#f0faf1", dark: "#1b2a1f"),
        Option(key: "blue", name: "あお", light: "#eff7fd", dark: "#1a2531"),
        Option(key: "aqua", name: "みずいろ", light: "#ecf8f6", dark: "#192a27"),
        Option(key: "lavender", name: "ラベンダー", light: "#f4f0fd", dark: "#231f31"),
        Option(key: "lilac", name: "ライラック", light: "#f9f1fa", dark: "#2a2030"),
        Option(key: "gray", name: "ライトグレー", light: "#f3f4f7", dark: "#2a2b30"),
        Option(key: "beige", name: "ベージュ", light: "#f8f4ed", dark: "#292419"),
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
    @AppStorage("startMonday") private var startMonday = false
    let title: String
    @Binding var selection: String

    var body: some View {
        let bg = CalendarBackground.color(selection)
        NavigationStack {
            VStack(spacing: 0) {
                Divider()
                MonthView(anchor: Rules.today(), startMonday: startMonday, summaryOn: false, selectedDate: nil,
                          onSelectDay: { _ in }, onSelectEvent: { _ in }, onTapEvent: { _, _ in }, onDropEvent: { _, _ in },
                          onSelectPayday: { _ in }, onLongPressDay: { _ in })
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
