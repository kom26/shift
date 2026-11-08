import SwiftUI

/// 読み取った時間が24時をこえるとき、取り込み方をまとめて確認する。
/// 種類(日付をまたぐ / 開始が24時以降)ごとに 1 回選ぶ。種類が2つあるときは、1つずつ順に選んで決める。時間が違っても、同じ種類なら同じ選び方になる
struct DaySpanSheet: View {
    let groups: [OvernightGroup]
    @Binding var choices: OvernightChoices
    /// 読み取った 1 行から、取り込んだときと同じ予定を作る(バーの見た目を、実際のカレンダーと同じにするため)
    let makeEvent: (ShiftLine) -> ShiftEvent?
    @Environment(\.dismiss) private var dismiss
    /// いま選んでいる種類(groups の何番目か)
    @State private var page = 0

    private struct Option: Identifiable {
        let id: String
        let event: ShiftEvent?
        let title: String
        let sub: String
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("日付をまたぐ予定の表記方法を選んでください。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(groups.indices.contains(page) ? [groups[page]] : []) { group in
                    Section {
                        exampleRow(group)
                        ForEach(options(for: group)) { o in optionRow(o, group: group) }
                    } header: {
                        Text((group.kind == .lateEnd ? "日付をまたぐ予定" : "開始が24時以降の予定") + "　\(group.dayCount)件"
                             + (groups.count > 1 ? "　(\(page + 1)/\(groups.count))" : ""))
                    }
                }
            }
            .navigationTitle("日またぎの確認")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if page > 0 {
                    ToolbarItem(placement: .cancellationAction) { Button("戻る") { page -= 1 } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if page < groups.count - 1 {
                        Button("決定") { page += 1 }
                    } else {
                        Button("決定") { dismiss() }
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Color(.systemGroupedBackground))
    }

    /// 最初の 1 件を、例として見せる(全部の日付は出さない)
    @ViewBuilder
    private func exampleRow(_ group: OvernightGroup) -> some View {
        if let p = group.patterns.first, let date = p.dates.first {
            Text("例:" + shortDate(date) + p.start + "〜" + p.end)
                .font(.app(15, weight: .semibold))
        }
    }

    private func shortDate(_ ds: String) -> String {
        let p = Rules.ymd(ds)
        let wd = Rules.weekdayLabels(startMonday: false)[Rules.weekday(ds)]
        return "\(p.month)/\(p.day)(\(wd))"
    }

    private func isOn(_ id: String, group: OvernightGroup) -> Bool {
        group.kind == .lateEnd ? choices.lateEnd.rawValue == id : choices.afterMidnight.rawValue == id
    }

    private func optionRow(_ o: Option, group: OvernightGroup) -> some View {
        let on = isOn(o.id, group: group)
        return Button {
            if group.kind == .lateEnd {
                choices.lateEnd = LateEndChoice(rawValue: o.id) ?? .fit
            } else {
                choices.afterMidnight = AfterMidnightChoice(rawValue: o.id) ?? .keep
            }
        } label: {
            HStack(spacing: 12) {
                if let event = o.event { BarLookPreview(event: event) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(o.title).font(.app(15, weight: .bold)).foregroundStyle(.primary)
                    Text(o.sub).font(.app(11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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

    /// その選び方で取り込んだときの予定(代表の時間と日付で作る)
    private func event(for group: OvernightGroup, option id: String) -> ShiftEvent? {
        guard let p = group.representative, let date = p.dates.first else { return nil }
        var c = OvernightChoices()
        if group.kind == .lateEnd {
            c.lateEnd = LateEndChoice(rawValue: id) ?? .fit
        } else {
            c.afterMidnight = AfterMidnightChoice(rawValue: id) ?? .keep
        }
        let line = ShiftLine(date: date, start: p.start, end: p.end, off: false)
        return makeEvent(ShiftLineImport.resolved(line, c))
    }

    private func options(for group: OvernightGroup) -> [Option] {
        guard let p = group.representative, let s = Rules.minutes(p.start), let e = Rules.minutes(p.end) else { return [] }
        let range = p.start + "〜" + p.end
        let nextEnd = e >= 1440 ? ShiftLineImport.timeText(e - 1440) : p.end
        switch group.kind {
        case .lateEnd:
            return [
                Option(id: LateEndChoice.fit.rawValue, event: event(for: group, option: LateEndChoice.fit.rawValue),
                       title: "1日に収める", sub: range + " のまま、その日の予定にします"),
                Option(id: LateEndChoice.cross.rawValue, event: event(for: group, option: LateEndChoice.cross.rawValue),
                       title: "日またぎにする", sub: p.start + "〜翌日" + nextEnd + " の、2日にまたがる予定にします"),
            ]
        case .afterMidnight:
            let nextStart = ShiftLineImport.timeText(max(0, s - 1440))
            return [
                Option(id: AfterMidnightChoice.keep.rawValue, event: event(for: group, option: AfterMidnightChoice.keep.rawValue),
                       title: range + " のまま", sub: "その日の予定として、" + p.start + "から" + p.end + "までにします"),
                Option(id: AfterMidnightChoice.cross.rawValue, event: event(for: group, option: AfterMidnightChoice.cross.rawValue),
                       title: p.start + "〜" + nextEnd + " の日またぎ", sub: "その日の" + p.start + "に始まり、翌日" + nextEnd + "に終わります"),
                Option(id: AfterMidnightChoice.next.rawValue, event: event(for: group, option: AfterMidnightChoice.next.rawValue),
                       title: nextStart + "〜" + nextEnd + "(翌日の予定)", sub: "日付が翌日になります。翌日の予定として入ります"),
            ]
        }
    }
}
