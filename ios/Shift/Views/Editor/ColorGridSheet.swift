import SwiftUI

/// 「カスタム色」の行。タップすると、色のグリッドの画面が開く
struct CustomColorButton: View {
    @Binding var color: String
    /// アイコンの色を選ぶときは、そのアイコンの記号の名前(下のプレビューを、バーではなくアイコンにする)
    var iconName: String?
    /// 開始・締切の色を選ぶときは、バーの見え方を矢印形のタグにする
    var taskLook = false
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            HStack(spacing: 8) {
                Text("カスタム色").foregroundStyle(Color.primary)
                Spacer()
                ColorDot(hex: color, size: 22)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .sheet(isPresented: $open) { ColorGridSheet(color: $color, iconName: iconName, taskLook: taskLook) }
    }
}

/// カスタム色を選ぶ。グリッドの 1 色を押して選び、下の「確定」で決める。
/// 左上のキャンセルや、画面を下げて閉じたときは、色は変わらない。
/// 選んだ色は、そのまま「元の色」になり、実際のバーでの見え方は、下のプレビューで確かめられる
struct ColorGridSheet: View {
    @Binding var color: String
    let iconName: String?
    let taskLook: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var picked: String

    init(color: Binding<String>, iconName: String? = nil, taskLook: Bool = false) {
        _color = color
        self.iconName = iconName
        self.taskLook = taskLook
        _picked = State(initialValue: color.wrappedValue)
    }

    private static let columns = 12

    /// 1 行目は白から黒まで、残りの 9 行は 12 色の色相を、濃い色から薄い色へ
    static let cells: [String] = {
        var list: [String] = []
        for i in 0..<columns {
            let v = 1 - Double(i) / Double(columns - 1)
            list.append(Color(hue: 0, saturation: 0, brightness: v).toHex())
        }
        let hues: [Double] = [200, 218, 252, 282, 328, 4, 22, 38, 48, 60, 72, 110]
        for row in 0..<9 {
            let saturation = 0.9 - 0.08 * Double(row)
            let brightness = 0.35 + 0.075 * Double(row)
            for h in hues {
                list.append(Color(hue: h / 360, saturation: saturation, brightness: brightness).toHex())
            }
        }
        return list
    }()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                grid
                bottomBar
                // 画面を内容の高さにして、グリッドとボタンのあいだに空きを作らない
                Spacer(minLength: 0)
            }
            .padding(16)
            .navigationTitle("カスタム色")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
            }
        }
        .presentationDetents([.height(560), .large])
        .presentationBackground(Color(.systemBackground))
    }

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: Self.columns), spacing: 0) {
            ForEach(Self.cells, id: \.self) { hex in
                Button { picked = hex } label: {
                    Color(hex: hex)
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            if hex == picked {
                                Rectangle().strokeBorder(Color.white, lineWidth: 3)
                                    .overlay(Rectangle().strokeBorder(Color.black.opacity(0.5), lineWidth: 1).padding(3))
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(hex)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    /// 「選択中」の文字は、選んだ色の上で読める色(明るい色なら濃く、暗い色なら白)
    private var pickedTextColor: Color {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(Color(hex: picked)).getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.299 * r + 0.587 * g + 0.114 * b > 0.6 ? Color.black.opacity(0.7) : Color.white
    }

    /// 左: 選んだ色 / 真ん中: バーの見え方 / 右: 確定
    private var bottomBar: some View {
        // 「選択中」の四角・バーの見え方・「確定」は、同じ高さ(52)の帯の真ん中にそろえる。「選択中」の文字は、四角の下にはみ出す
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(hex: picked))
                .frame(width: 52, height: 52)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(.separator), lineWidth: 1))
                .overlay { Text("選択中").font(.app(10, weight: .semibold)).foregroundStyle(pickedTextColor) }
            VStack(spacing: 0) {
                if let iconName {
                    // アイコンの色を選んでいるときは、そのアイコンの見た目を出す
                    Image(systemName: iconName)
                        .font(.system(size: 20))
                        .foregroundStyle(Color(hex: picked))
                        .frame(width: 44, height: 44)
                        .background(Color(hex: picked).opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
                        .frame(maxWidth: .infinity, minHeight: 30)
                } else if taskLook {
                    // 開始(右向きの白抜き)と締切(左向きの塗り)を、点線でつないだ、3日以上の見え方
                    HStack(spacing: 0) {
                        TaskTagBar(title: "開始", color: picked, isStart: true, height: 24, fontSize: 12)
                            .frame(width: 58)
                        Line()
                            .stroke(Color(hex: picked), style: StrokeStyle(lineWidth: 1.5, dash: [1.5, 3.5], dashPhase: 0))
                            .frame(height: 1.5)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 4)
                        TaskTagBar(title: "締切", color: picked, isStart: false, height: 24, fontSize: 12)
                            .frame(width: 58)
                    }
                    .frame(minHeight: 30)
                    .environment(\.calendarBackground, Color(.systemBackground))
                } else {
                    Text("22:00-06:30")
                        .font(.bar(13, weight: .bold))
                        .foregroundStyle(EventColor.text(picked))
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                        .background(EventColor.fill(picked), in: RoundedRectangle(cornerRadius: 6))
                        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(.separator), lineWidth: 1))
                }
            }
            .frame(height: 52)
            // 見た目は、四角・確定と同じ高さの真ん中に置き、説明の文字は、その下に離して出す
            .overlay(alignment: .bottom) {
                Text(iconName != nil ? "アイコンの見た目" : "バーの見え方")
                    .font(.app(10))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .offset(y: 20)
            }
            Button {
                color = picked
                dismiss()
            } label: {
                Text("確定")
                    .font(.app(16, weight: .bold))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 22)
                    .frame(height: 52)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
    }
}

/// 横一直線(点線の下書き)
private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}
