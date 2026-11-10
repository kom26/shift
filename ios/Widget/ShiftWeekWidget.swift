import SwiftUI
import WidgetKit
import AppIntents

struct MediumWeekView: View {
    let content: WeekContent
    let offset: Int

    private let barH: CGFloat = 15
    private let laneGap: CGFloat = 2
    private let sidePad: CGFloat = 12

    var body: some View {
        VStack(spacing: 0) {
            header
            GeometryReader { geo in
                let colW = geo.size.width / 7
                ZStack(alignment: .topLeading) {
                    if let t = content.todayCol {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Theme.accentSoft)
                            .frame(width: colW, height: geo.size.height)
                            .offset(x: colW * CGFloat(t))
                    }
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { i in
                            VStack(spacing: 0) {
                                Text(["日", "月", "火", "水", "木", "金", "土"][weekdayIndex(i)])
                                    .font(.app(9))
                                    .foregroundStyle(content.dayTypes[i] == .normal ? Color.secondary : content.dayTypes[i].color)
                                Text("\(content.dayNumbers[i])")
                                    .font(.app(12, weight: content.todayCol == i ? .heavy : .semibold).monospacedDigit())
                                    .foregroundStyle(content.todayCol == i ? Theme.accent
                                                     : (content.dayTypes[i] == .normal ? Color.primary : content.dayTypes[i].color))
                            }
                            .frame(width: colW)
                        }
                    }
                    bars(colW: colW)
                        .offset(y: 31)
                    dayLinks(colW: colW, height: geo.size.height)
                }
            }
            footer
        }
        .padding(.horizontal, sidePad)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    /// 曜日の見出し。週の始まりが日曜か月曜かは、1日目の曜日から決める
    private func weekdayIndex(_ i: Int) -> Int {
        (Rules.weekday(content.days[0]) + i) % 7
    }

    private var header: some View {
        HStack(spacing: 5) {
            Text(content.title)
                .font(.app(12.5, weight: .bold))
                .lineLimit(1)
            Spacer(minLength: 0)
            if offset != 0 {
                Button(intent: ResetWeekIntent()) { WidgetBackLabel(text: "今週へ") }
                    .buttonStyle(.plain)
            }
            Button(intent: StepWeekIntent(delta: -1)) { WidgetStepButtonLabel(systemName: "chevron.left") }
                .buttonStyle(.plain)
            Button(intent: StepWeekIntent(delta: 1)) { WidgetStepButtonLabel(systemName: "chevron.right") }
                .buttonStyle(.plain)
        }
        .frame(height: 22)
    }

    @ViewBuilder
    private var footer: some View {
        if content.hours != nil || content.pay != nil {
            HStack {
                if let hours = content.hours {
                    Text("労働時間 ").font(.app(10)).foregroundStyle(.secondary)
                        + Text(hours).font(.app(10, weight: .semibold))
                }
                Spacer()
                if let pay = content.pay {
                    Text("見込み給料 ").font(.app(10)).foregroundStyle(.secondary)
                        + Text(pay).font(.app(10, weight: .semibold))
                }
            }
            .monospacedDigit()
            .frame(height: 14)
        }
    }

    private func bars(colW: CGFloat) -> some View {
        // 「00:00-00:00」が1日分の幅に収まる大きさ。月表示のバーと同じ考え方
        let size = min(9, FixedWidthTime.fitSize(width: colW - 2 - 4))
        return ZStack(alignment: .topLeading) {
            ForEach(content.bars) { b in
                Group {
                    if b.showsTime {
                        FixedWidthTimeText(text: b.text, size: size)
                    } else {
                        Text(b.text).font(.bar(size, weight: .bold)).lineLimit(1)
                    }
                }
                .padding(.leading, b.taskStart == false ? 6 : 2)
                .padding(.trailing, b.taskStart == true ? 6 : 2)
                .frame(width: max(0, colW * CGFloat(b.span) - 2), height: barH, alignment: .leading)
                .clipped()
                .foregroundStyle(EventColor.text(b.color))
                .background { barBackground(b) }
                .offset(x: colW * CGFloat(b.col) + 1, y: CGFloat(b.lane) * (barH + laneGap))
            }
        }
    }

    /// 予定は角丸の帯。開始・締切は、カレンダーと同じ矢印形(開始は白抜きで右向き、締切は塗りで左向き)
    @ViewBuilder
    private func barBackground(_ b: WeekBar) -> some View {
        if let isStart = b.taskStart {
            let shape = ArrowTagShape(pointsRight: isStart, notch: 5)
            shape.fill(isStart ? Color(.systemBackground) : EventColor.fill(b.color))
                .overlay { if isStart { shape.stroke(Color(hex: b.color), lineWidth: 1.2) } }
        } else {
            RoundedRectangle(cornerRadius: 4).fill(EventColor.fill(b.color))
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 4))
        }
    }

    /// 日付ごとのタップ領域。その日の予定一覧をアプリで開く
    private func dayLinks(colW: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { i in
                Link(destination: widgetDayURL(content.days[i], calendarId: content.calendarId)) {
                    Color.clear.contentShape(Rectangle())
                }
                .frame(width: colW, height: height)
            }
        }
    }
}
