import SwiftUI

/// 下部エリアのアラームページ。時間を合わせて「セット」を押すと、そのままスタンプモードに入る
struct AlarmPage: View {
    @Binding var stamp: AlarmPreset?

    @State private var kind: AlarmPreset.Kind = .clock
    @State private var hour = 6
    @State private var minute = 30
    @State private var typed = ""
    @FocusState private var typing: Bool

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
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                wheel
                    .opacity(active ? 0.45 : 1)
                    .allowsHitTesting(!active)
                VStack(spacing: 8) {
                    Picker("種類", selection: $kind) {
                        Text("時刻").tag(AlarmPreset.Kind.clock)
                        Text("シフト前").tag(AlarmPreset.Kind.beforeShift)
                    }
                    .pickerStyle(.segmented)
                    .disabled(active)
                    .onChange(of: kind) { _, new in
                        hour = min(hour, new == .clock ? 23 : 12)
                        if new == .beforeShift { minute = (minute / 5) * 5; if hour == 0 && minute == 0 { hour = 3 } }
                        typed = ""
                    }
                    Button { start() } label: {
                        Text(active ? "セット中…" : "セット")
                            .font(.app(15, weight: .bold))
                            .foregroundStyle(active ? Color.secondary : Theme.onAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(active ? Color(.secondarySystemFill) : Theme.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(active || (kind == .beforeShift && totalMinutes == 0))
                }
                .frame(width: 124)
            }
            .frame(height: 100)
            if active {
                HStack(spacing: 12) {
                    HStack(spacing: 4) { guideTag("タップ"); Text("セットする") }
                    HStack(spacing: 4) { guideTag("もう一度タップ"); Text("解除する") }
                    Spacer(minLength: 0)
                }
                .font(.app(10))
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完了") { typing = false; typed = "" }
            }
        }
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

    private var wheel: some View {
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
        .frame(height: 100)
        .compositingGroup()
        .clipped()
        // 中央の行をタップすると数字で手入力できる(ロールの操作はそのまま通す)
        .simultaneousGesture(SpatialTapGesture().onEnded { v in
            if abs(v.location.y - 50) < 17 {
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
