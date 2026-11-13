import SwiftUI

/// 共有カレンダーの設定の「自分だけの見え方」。24時をこえる予定を、この端末でどう見せるか選ぶ
/// extra: 段の下に足す行(参加者ごとの色)
struct OvernightLookSection<Extra: View>: View {
    @Binding var value: OvernightDisplay
    @ViewBuilder var extra: () -> Extra

    var body: some View {
        Section {
            NavigationLink {
                OvernightLookView(kind: .lateEnd, value: $value)
            } label: {
                LabeledContent("日付をまたぐ予定", value: OvernightNames.name(value.lateEnd))
            }
            NavigationLink {
                OvernightLookView(kind: .afterMidnight, value: $value)
            } label: {
                LabeledContent("開始が24時以降の予定", value: OvernightNames.name(value.afterMidnight))
            }
            extra()
        } header: {
            Text("自分だけの見え方")
        } footer: {
            Text("この共有カレンダーを、あなたが見るときの表示だけが変わります。ほかの人の画面や、予定の中身は変わりません。")
        }
    }

}

enum OvernightNames {
    static func name(_ c: LateEndChoice?) -> String {
        switch c {
        case nil: "予定作成者の表示のまま"
        case .fit?: "その日に収める"
        case .cross?: "日またぎ"
        }
    }

    static func name(_ c: AfterMidnightChoice?) -> String {
        switch c {
        case nil: "予定作成者の表示のまま"
        case .keep?: "24:00〜30:00"
        case .cross?: "日またぎ"
        case .next?: "翌日の予定"
        }
    }
}

/// 選ぶ画面。選んだらすぐ反映する
struct OvernightLookView: View {
    let kind: OvernightKind
    @Binding var value: OvernightDisplay

    private struct Option: Identifiable {
        let id: String
        let title: String
        let sub: String
        let event: ShiftEvent?
        let isOn: Bool
        let pick: () -> Void
    }

    var body: some View {
        List {
            Section {
                ForEach(options) { row($0) }
            } header: {
                Text(kind == .lateEnd ? "例:3日 22:00〜30:00、3日 22:00〜4日 06:00" : "例:3日 24:00〜30:00")
                    .textCase(nil)
            } footer: {
                if kind == .afterMidnight {
                    Text("翌日の00:00からで入っている予定は、ふつうの予定と見分けがつかないため、そのまま出します。")
                }
            }
        }
        .navigationTitle(kind == .lateEnd ? "日付をまたぐ予定" : "開始が24時以降の予定")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var options: [Option] {
        let mine = "予定を作った人が選んだ表示で出します"
        switch kind {
        case .lateEnd:
            return [
                Option(id: "none", title: "予定作成者の表示のまま", sub: mine, event: nil,
                       isOn: value.lateEnd == nil, pick: { value.lateEnd = nil }),
                Option(id: "fit", title: "その日に収める", sub: "22:00〜30:00 のまま、始まった日の予定として出します",
                       event: sample(late: .fit), isOn: value.lateEnd == .fit, pick: { value.lateEnd = .fit }),
                Option(id: "cross", title: "日またぎにする", sub: "22:00〜翌日06:00 の、2日にまたがる予定として出します",
                       event: sample(late: .cross), isOn: value.lateEnd == .cross, pick: { value.lateEnd = .cross }),
            ]
        case .afterMidnight:
            return [
                Option(id: "none", title: "予定作成者の表示のまま", sub: mine, event: nil,
                       isOn: value.afterMidnight == nil, pick: { value.afterMidnight = nil }),
                Option(id: "keep", title: "24:00〜30:00 のまま", sub: "始まった日の予定として、24:00から30:00までで出します",
                       event: sample(after: .keep), isOn: value.afterMidnight == .keep, pick: { value.afterMidnight = .keep }),
                Option(id: "cross", title: "24:00〜06:00 の日またぎ", sub: "始まった日の24:00から、翌日06:00までの予定として出します",
                       event: sample(after: .cross), isOn: value.afterMidnight == .cross, pick: { value.afterMidnight = .cross }),
                Option(id: "next", title: "00:00〜06:00(翌日の予定)", sub: "翌日の予定として出します",
                       event: sample(after: .next), isOn: value.afterMidnight == .next, pick: { value.afterMidnight = .next }),
            ]
        }
    }

    private func row(_ o: Option) -> some View {
        let colW = floor(UIScreen.main.bounds.width / 7)
        return Button(action: o.pick) {
            HStack(spacing: 12) {
                Group {
                    if let e = o.event {
                        BarLookPreview(event: e)
                    } else {
                        Text("作成者のまま")
                            .font(.app(10))
                            .foregroundStyle(.secondary)
                            .frame(width: colW * 2, height: 37)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                .frame(width: colW * 2, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(o.title).font(.app(15, weight: .bold)).foregroundStyle(.primary)
                    Text(o.sub).font(.app(11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "checkmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .opacity(o.isOn ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 見本の予定(その選び方で、カレンダーにどう出るか)
    private func base(start: String, end: String) -> ShiftEvent {
        var e = ShiftEvent.new(on: Rules.today())
        e.allDay = false
        e.startTime = start
        e.endTime = end
        e.color = "#7a62d9"
        return e
    }

    private func sample(late: LateEndChoice) -> ShiftEvent {
        OvernightDisplay(lateEnd: late).apply(base(start: "22:00", end: "30:00"))
    }

    private func sample(after: AfterMidnightChoice) -> ShiftEvent {
        OvernightDisplay(afterMidnight: after).apply(base(start: "24:00", end: "30:00"))
    }
}
