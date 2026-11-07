import SwiftUI

/// セット済みのアラームを直す・消す。日の一覧の上のアラームのチップから開く。
/// 「時刻」は時刻を、「予定前」は予定の何時間何分前かを直せて、スヌーズのオン・オフと長さもここで変えられる
struct AlarmEditSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let entry: AlarmEntry

    @State private var hour: Int
    @State private var minute: Int
    @State private var snoozeOn: Bool
    @State private var snooze: Int
    @State private var errorMessage: String?
    @State private var saving = false
    @State private var confirmDelete = false

    init(entry: AlarmEntry) {
        self.entry = entry
        _hour = State(initialValue: entry.minutes / 60)
        _minute = State(initialValue: entry.minutes % 60)
        let current = entry.snoozeMinutes ?? AlarmService.snoozeMinutes
        _snoozeOn = State(initialValue: current > 0)
        _snooze = State(initialValue: AlarmService.snoozeOptions.contains(current) ? current : 9)
    }

    private var isClock: Bool { entry.kind == .clock }
    private var minutes: Int { hour * 60 + minute }
    private var spec: AlarmPreset { AlarmPreset(kind: entry.kind, minutes: minutes) }

    /// いまの設定で鳴る日時。予定がその日になければ nil
    private var fireDate: Date? { AlarmMath.fireDate(preset: spec, on: entry.date, events: store.events) }

    private var fireText: String {
        guard let d = fireDate else { return "その日に予定がありません" }
        let c = Calendar.current.dateComponents([.month, .day, .hour, .minute], from: d)
        return String(format: "%d/%d %d:%02d", c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
    }

    private var dateText: String {
        let p = Rules.ymd(entry.date)
        let wd = Rules.weekdayLabels(startMonday: false)[Rules.weekday(entry.date)]
        return "\(p.month)月\(p.day)日(\(wd))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent(isClock ? "かけた日" : "予定の日", value: dateText)
                    LabeledContent("鳴る時刻", value: fireText)
                }
                Section {
                    wheel
                } header: {
                    Text(isClock ? "時刻" : "予定の何時間何分前")
                } footer: {
                    if !isClock { Text("予定の時間を直すと、鳴る時刻も自動で合わせます。") }
                }
                Section {
                    Toggle("スヌーズ", isOn: $snoozeOn)
                    if snoozeOn {
                        Picker("スヌーズの長さ", selection: $snooze) {
                            ForEach(AlarmService.snoozeOptions, id: \.self) { Text("\($0)分").tag($0) }
                        }
                    }
                } footer: {
                    Text("アラームが鳴ったときに「スヌーズ」ボタンが出て、押すとこの分数あとにもう一度鳴ります。")
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
                Section {
                    Button("このアラームを削除", role: .destructive) { confirmDelete = true }
                }
            }
            .navigationTitle("アラームを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { Task { await save() } }
                        .disabled(saving || fireDate == nil || (!isClock && minutes == 0))
                }
            }
            // 画面の真ん中に出す確認(上に出ないように、アラートにしてある)
            .alert("このアラームを削除しますか?", isPresented: $confirmDelete) {
                Button("削除", role: .destructive) {
                    Task {
                        await AlarmService.shared.remove(entry, store: store)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        dismiss()
                    }
                }
                Button("キャンセル", role: .cancel) {}
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Color(.systemGroupedBackground))
    }

    /// セット画面と同じ、ドラムロール。「時刻」は時:分、「予定前」は何時間何分前
    private var wheel: some View {
        HStack(spacing: 0) {
            Picker("時", selection: $hour) {
                ForEach(0...(isClock ? 23 : 12), id: \.self) { Text(isClock ? String(format: "%02d", $0) : "\($0)").tag($0) }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            if isClock {
                Text(":").font(.app(22, weight: .bold))
            } else {
                Text("時間").font(.app(14)).foregroundStyle(.secondary)
            }
            Picker("分", selection: $minute) {
                ForEach(isClock ? Array(0..<60) : Array(stride(from: 0, to: 60, by: 5)), id: \.self) {
                    Text(String(format: "%02d", $0)).tag($0)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            if !isClock { Text("分前").font(.app(14)).foregroundStyle(.secondary) }
        }
        .frame(height: 150)
        .compositingGroup()
        .clipped()
    }

    private func save() async {
        saving = true
        errorMessage = nil
        let outcome = await AlarmService.shared.update(entry, spec: spec, snooze: snoozeOn ? snooze : 0, store: store)
        saving = false
        switch outcome {
        case .set:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            dismiss()
        case .past: errorMessage = "過ぎた時刻には、設定できません"
        case .noShift: errorMessage = "その日に予定がないので、設定できません"
        case .denied: errorMessage = "アラームの許可が必要です。設定アプリで、許可してください"
        case .removed, .unsupported, .failed: errorMessage = "アラームを変更できませんでした"
        }
    }
}
