import SwiftUI

/// 読み取った予定と、同じ日・同じ職場(職場がなければ同じラベル)のいまの予定が重なるときの扱い
enum DupChoice: String, CaseIterable {
    /// いまの予定を残す(読み取った予定は追加しない)
    case keep
    /// 読み取った予定に置き換える(いまの予定は消す)
    case replace
    /// どちらも残す
    case both
}

/// その日だけの重複の確認。いまの予定と読み取った予定のバーを見比べて、どうするか選ぶ
struct DupChoiceSheet: View {
    let dateText: String
    /// 職場がなくラベルでの重複か
    let byLabel: Bool
    let existing: [ShiftEvent]
    let incoming: ShiftEvent
    @Binding var choice: DupChoice
    @Environment(\.dismiss) private var dismiss

    private var sameTime: Bool {
        existing.contains { $0.allDay == incoming.allDay && $0.startTime == incoming.startTime && $0.endTime == incoming.endTime }
    }

    private static let options: [(DupChoice, String, String)] = [
        (.keep, "いまの予定を残す", "読み取った予定は、追加しません"),
        (.replace, "読み取った予定に置き換える", "いまの予定を消して、読み取った予定を入れます"),
        (.both, "どちらも残す", "両方とも、カレンダーに入ります"),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(byLabel ? "同じ日に同じラベルの予定が既にあります。\nどの予定を残すか選択してください。"
                                 : "同じ日に同じ職場の予定が既にあります。\nどの予定を残すか選択してください。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section {
                    ForEach(existing) { e in barRow("いまの予定", e) }
                    barRow("読み取った予定", incoming)
                    if sameTime {
                        Text("時間も同じです").font(.app(11, weight: .bold)).foregroundStyle(.red)
                    }
                }
                Section {
                    ForEach(Self.options, id: \.0) { option in optionRow(option.0, option.1, option.2) }
                }
            }
            .navigationTitle(dateText + "の重複")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color(.systemGroupedBackground))
    }

    private func barRow(_ label: String, _ event: ShiftEvent) -> some View {
        var e = event
        if e.title.isEmpty { e.title = "予定" }
        return HStack(spacing: 10) {
            Text(label).font(.app(12)).foregroundStyle(.secondary).frame(width: 96, alignment: .leading)
            BarLookPreview(event: e)
            Spacer(minLength: 0)
        }
    }

    private func optionRow(_ value: DupChoice, _ title: String, _ sub: String) -> some View {
        let on = choice == value
        return Button { choice = value } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.app(15, weight: .semibold)).foregroundStyle(.primary)
                    Text(sub).font(.app(11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(on ? Theme.accent : Color.secondary.opacity(0.5))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(on ? Theme.accent.opacity(0.07) : nil)
    }
}
