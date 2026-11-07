import SwiftUI

/// 下部エリアのアラームページ。時間を合わせて「セット」を押すと、そのままスタンプモードに入る
struct AlarmPage: View {
    @Binding var stamp: AlarmPreset?

    @State private var kind: AlarmPreset.Kind = .clock
    /// 時刻の初期値は、いまの時刻。予定前の初期値は、2 時間前
    @State private var hour = Calendar.current.component(.hour, from: Date())
    @State private var minute = Calendar.current.component(.minute, from: Date())
    @State private var typed = ""
    @FocusState private var typing: Bool
    /// スヌーズの分数(0 はスヌーズなし)。これからセットするアラームに使う
    @AppStorage(AlarmService.snoozeKey) private var snoozeMinutes = 9

    private var active: Bool { stamp != nil }
    private var maxHour: Int { kind == .clock ? 23 : 12 }
    private var minuteItems: [Int] { kind == .clock ? Array(0..<60) : Array(stride(from: 0, to: 60, by: 5)) }

    private var totalMinutes: Int { hour * 60 + minute }

    var body: some View {
        if AlarmService.isSupported {
            content
        } else {
            Text("アラームは iOS 26 以降で使えます")
                .font(.app(12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var content: some View {
        // 下の余白が余らないよう、使える高さいっぱいに、ドラムロールと右の操作を広げる
        GeometryReader { geo in
            // 上の余白 8 + 案内の行 16 + 間 4 + 下の余白 6 を除いた高さを、ロールと右の操作に使う
            let h = max(Self.minBodyHeight, geo.size.height - 8 - 16 - 4 - 6)
            VStack(spacing: 4) {
                HStack(spacing: 12) {
                    wheel(height: h)
                        .opacity(active ? 0.45 : 1)
                        .allowsHitTesting(!active)
                    controls(height: h)
                        .frame(width: 168)
                }
                .frame(height: h)
                HStack(spacing: 12) {
                    if active {
                        HStack(spacing: 4) { guideTag("タップ"); Text("セットする") }
                        HStack(spacing: 4) { guideTag("もう一度タップ"); Text("解除する") }
                    } else {
                        // セットを押すと、どうなるかの案内
                        Text("セットを押して、日付をタップでアラームをかける")
                    }
                    Spacer(minLength: 0)
                }
                .font(.app(10))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(.secondary)
                .frame(height: 16)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 6)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .keyboardDismissBar { typing = false; typed = "" }
    }

    private static let minBodyHeight: CGFloat = 104

    /// 右の操作。上から、時刻・予定前の切り替え、スヌーズ、セットのボタン(高さに合わせて間を広げる)
    private func controls(height: CGFloat) -> some View {
        VStack(spacing: 4) {
            TwoWayPicker("種類", selection: $kind, first: ("時刻", AlarmPreset.Kind.clock), second: ("予定前", AlarmPreset.Kind.beforeShift))
            .disabled(active)
            .onChange(of: kind) { _, new in
                if new == .clock {
                    let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
                    hour = now.hour ?? 6
                    minute = now.minute ?? 0
                } else {
                    hour = 2
                    minute = 0
                }
                typed = ""
            }
            Spacer(minLength: 0)
            // セット中は、スヌーズの行の代わりに、下に完了ボタンを出す(高さが足りるように)
            if !active { snoozeRow }
            Spacer(minLength: 0)
            Button { start() } label: {
                Text(active ? "セット中…" : "セット")
                    .font(.app(16, weight: .bold))
                    .foregroundStyle(active ? Color.secondary : Theme.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(active ? Color(.secondarySystemFill) : Theme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(active || (kind == .beforeShift && totalMinutes == 0))
            if active {
                Button { finish() } label: {
                    Text("完了")
                        .font(.app(16, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .overlay(Capsule().strokeBorder(Theme.accent, lineWidth: 1.5))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: height)
    }

    /// スヌーズ。トグルでオン・オフし、オンのときだけ、分数を選べる
    private var snoozeRow: some View {
        let isOn = Binding<Bool>(
            get: { snoozeMinutes > 0 },
            set: { on in
                snoozeMinutes = on ? 9 : 0
            })
        return HStack(spacing: 6) {
            Text("スヌーズ").font(.app(13, weight: .semibold)).lineLimit(1).fixedSize()
            Spacer(minLength: 0)
            Toggle("スヌーズ", isOn: isOn)
                .labelsHidden()
                .fixedSize()
        }
        .frame(height: 31)
    }

    /// スタンプモードを終える
    private func finish() {
        stamp = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func start() {
        stamp = AlarmPreset(kind: kind, minutes: totalMinutes)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func guideTag(_ text: String) -> some View {
        Text(text)
            .font(.app(9.5, weight: .semibold))
            .foregroundStyle(Theme.monthText)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Theme.monthFill, in: RoundedRectangle(cornerRadius: 4))
    }

    // MARK: ドラムロール + 手入力

    private func wheel(height: CGFloat) -> some View {
        let hourBinding = Binding<Int>(get: { hour }, set: { setTime(h: $0, m: minute) })
        let minuteBinding = Binding<Int>(get: { minute }, set: { setTime(h: hour, m: $0) })
        return ZStack {
            HStack(spacing: 0) {
                Picker("時", selection: hourBinding) {
                    ForEach(0...maxHour, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
                if kind == .beforeShift { Text("時間").font(.app(12)).foregroundStyle(.secondary) } else {
                    Text(":").font(.app(20, weight: .bold))
                }
                Picker("分", selection: minuteBinding) {
                    ForEach(minuteItems, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
                if kind == .beforeShift { Text("分前").font(.app(12)).foregroundStyle(.secondary) }
            }
            TextField("", text: typedBinding)
                .keyboardType(.numberPad)
                .focused($typing)
                .frame(width: 1, height: 1)
                .opacity(0.02)
                .accessibilityHidden(true)
        }
        .frame(height: height)
        .compositingGroup()
        .clipped()
        // 中央の行をタップすると数字で手入力できる(ロールの操作はそのまま通す)
        .simultaneousGesture(SpatialTapGesture().onEnded { v in
            if abs(v.location.y - height / 2) < 17 {
                typed = String(format: "%02d%02d", hour, minute)
                typing = true
            }
        })
    }

    private func setTime(h: Int, m: Int) {
        hour = min(max(h, 0), maxHour)
        minute = min(max(m, 0), 59)
        typed = String(format: "%02d%02d", hour, minute)
    }

    private var typedBinding: Binding<String> {
        Binding(
            get: { typed },
            set: { input in
                var digits = String(input.filter { $0.isASCII && $0.isNumber })
                if digits.count > 4 { digits = String(digits.dropFirst(4).prefix(4)) }
                if digits.isEmpty {
                    hour = 0
                    minute = 0
                    typed = ""
                } else if digits.count == 4 {
                    let v = Int(digits) ?? 0
                    let h = v / 100, m = v % 100
                    if h <= maxHour, m <= 59 {
                        setTime(h: h, m: m)
                    } else {
                        UINotificationFeedbackGenerator().notificationOccurred(.error)
                        typed = String(format: "%02d%02d", hour, minute)
                    }
                } else {
                    typed = digits
                }
            })
    }
}
