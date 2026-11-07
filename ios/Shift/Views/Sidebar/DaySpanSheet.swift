import SwiftUI

/// 読み取った時間が24時をこえるとき、取り込み方をまとめて確認する。
/// 種類(終了が24時をこえる / 開始が24時以降)ごとに 1 回選ぶ。時間が違っても、同じ種類なら同じ選び方になる
struct DaySpanSheet: View {
    let groups: [OvernightGroup]
    @Binding var choices: OvernightChoices
    @Environment(\.dismiss) private var dismiss

    private struct Option: Identifiable {
        let id: String
        let style: SpanMini.Style
        let title: String
        let sub: String
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("時間が24時をこえる予定があります。取り込み方を選んでください(あとから、1件ずつも直せます)。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(groups) { group in
                    Section {
                        ForEach(group.patterns) { p in patternRow(p) }
                        ForEach(options(for: group)) { o in optionRow(o, group: group) }
                    } header: {
                        Text(group.kind == .lateEnd ? "終了が24時をこえる予定(\(group.dayCount)日分)" : "開始が24時以降の予定(\(group.dayCount)日分)")
                    }
                }
                Section {
                    Text("時間の長さは、どれを選んでも同じです。カレンダーでの見え方と、予定がどの日に入るかが変わります。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("日またぎの確認")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("決定") { dismiss() } }
            }
        }
        .presentationDetents([.large])
    }

    private func patternRow(_ p: OvernightPattern) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(p.start + "〜" + p.end).font(.app(15, weight: .semibold))
                Text("×\(p.dates.count)").font(.app(13)).foregroundStyle(.secondary)
            }
            Text(p.dates.map(shortDate).joined(separator: "・"))
                .font(.app(11))
                .foregroundStyle(.secondary)
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
                SpanMini(style: o.style)
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

    private func options(for group: OvernightGroup) -> [Option] {
        guard let p = group.representative, let s = Rules.minutes(p.start), let e = Rules.minutes(p.end) else { return [] }
        let range = p.start + "〜" + p.end
        let nextEnd = e >= 1440 ? ShiftLineImport.timeText(e - 1440) : p.end
        switch group.kind {
        case .lateEnd:
            return [
                Option(id: LateEndChoice.fit.rawValue, style: .oneDay(p.start + "-" + p.end),
                       title: "1日に収める", sub: range + " のまま、その日の予定にします"),
                Option(id: LateEndChoice.cross.rawValue, style: .cross(p.start, "〜" + nextEnd),
                       title: "日またぎにする", sub: p.start + "〜翌日" + nextEnd + " の、2日にまたがる予定にします"),
            ]
        case .afterMidnight:
            let nextStart = ShiftLineImport.timeText(max(0, s - 1440))
            return [
                Option(id: AfterMidnightChoice.keep.rawValue, style: .oneDay(p.start + "-" + p.end),
                       title: range + " のまま", sub: "その日の予定として、" + p.start + "から" + p.end + "までにします"),
                Option(id: AfterMidnightChoice.cross.rawValue, style: .cross(p.start, "〜" + nextEnd),
                       title: p.start + "〜" + nextEnd + " の日またぎ", sub: "その日の" + p.start + "に始まり、翌日" + nextEnd + "に終わります"),
                Option(id: AfterMidnightChoice.next.rawValue, style: .nextDay(nextStart + "-" + nextEnd),
                       title: nextStart + "〜" + nextEnd + "(翌日の予定)", sub: "日付が翌日になります。翌日の予定として入ります"),
            ]
        }
    }
}

/// 2日分の小さなカレンダー。予定のバーが、1日の中か、日またぎか、翌日かを見せる
struct SpanMini: View {
    enum Style {
        case oneDay(String)
        case cross(String, String)
        case nextDay(String)
    }

    let style: Style

    private let barColor = Color(hex: "#bfd2f7")
    private let barText = Color(hex: "#2c4a8a")

    var body: some View {
        HStack(spacing: 0) {
            cell(0, label: "当日")
            Divider()
            cell(1, label: "翌日")
        }
        .frame(width: 132, height: 50)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.separator), lineWidth: 1))
    }

    private func cell(_ i: Int, label: String) -> some View {
        ZStack(alignment: .topLeading) {
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary).padding(.leading, 4).padding(.top, 3)
            bar(i).padding(.top, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func bar(_ i: Int) -> some View {
        switch style {
        case .oneDay(let t):
            if i == 0 { shape(t, left: true, right: true, leading: 3, trailing: 3) }
        case .cross(let a, let b):
            if i == 0 { shape(a, left: true, right: false, leading: 3, trailing: 0) } else { shape(b, left: false, right: true, leading: 0, trailing: 20) }
        case .nextDay(let t):
            if i == 0 {
                Text("翌日へ")
                    .font(.system(size: 8.5))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 16)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(.systemGray3), lineWidth: 1))
                    .padding(.horizontal, 3)
            } else {
                shape(t, left: true, right: true, leading: 3, trailing: 3)
            }
        }
    }

    private func shape(_ text: String, left: Bool, right: Bool, leading: CGFloat, trailing: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 8.5, weight: .bold))
            .foregroundStyle(barText)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.leading, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 16)
            .background(barColor, in: UnevenRoundedRectangle(topLeadingRadius: left ? 4 : 0, bottomLeadingRadius: left ? 4 : 0,
                                                              bottomTrailingRadius: right ? 4 : 0, topTrailingRadius: right ? 4 : 0))
            .padding(.leading, leading)
            .padding(.trailing, trailing)
    }
}
