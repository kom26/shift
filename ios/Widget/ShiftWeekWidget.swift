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
                                    // 日付の左にアラーム、右に給料日
                                    .overlay(alignment: .leading) { alarmMark(i) }
                                    .overlay(alignment: .trailing) { paydayMark(i) }
                            }
                            .frame(width: colW)
                        }
                    }
                    bars(colW: colW)
                        // 日付と 1 段目のバーの間を詰めて、下の記念日のアイコンとの間を空ける
                        .offset(y: 28)
                    // 記念日・誕生日は、アプリのカレンダーと同じく、日の列の右下に並べる
                    annivMarks(colW: colW, height: geo.size.height)
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

    /// 日付の左に出す、アラームのベル(日付から 2pt 離す)
    @ViewBuilder
    private func alarmMark(_ i: Int) -> some View {
        if i < content.marks.count, content.marks[i].alarm {
            Image(systemName: "bell.fill")
                .font(.system(size: 9))
                .foregroundStyle(Theme.alarm)
                .fixedSize()
                .alignmentGuide(.leading) { d in d[.trailing] + 2 }
        }
    }

    /// 日付の右に出す、給料日のコイン(日付から 2pt 離す)
    @ViewBuilder
    private func paydayMark(_ i: Int) -> some View {
        if i < content.marks.count, content.marks[i].payday {
            Image("CoinStack")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 8, height: 8)
                .foregroundStyle(Color(red: 0.95, green: 0.7, blue: 0.1))
                .alignmentGuide(.trailing) { d in d[.leading] - 2 }
        }
    }

    /// 日の列の右下に、記念日・誕生日のアイコンを右詰めで並べる(2 個まで。3 個目からは「+n」)
    private func annivMarks(colW: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { i in
                HStack(spacing: 1) {
                    if i < content.marks.count {
                        ForEach(content.marks[i].annivs) { a in
                            Image(a.asset)
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 8, height: 8)
                                .foregroundStyle(Color(hex: a.color))
                        }
                        if content.marks[i].annivMore > 0 {
                            Text("+\(content.marks[i].annivMore)")
                                .font(.app(7.5, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.trailing, 3)
                .padding(.bottom, 1)
                .frame(width: colW, height: height, alignment: .bottomTrailing)
            }
        }
        .allowsHitTesting(false)
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
            // カレンダーの切り替え(2 つ以上選んでいるときだけ)。小と同じく、いつも右上(前へ・次への右)
            if let sw = content.switcher {
                Button(intent: CycleCalendarIntent(size: "medium")) { WidgetCalendarSwitchLabel(sw: sw) }
                    .buttonStyle(.plain)
                    .padding(.leading, 2)
            }
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
            ForEach(content.bars.filter(\.link)) { b in linkBar(b, colW: colW, size: size) }
            // 5 件以上ある日は、4 段目に「ほか○件」
            ForEach(Array(content.more.enumerated()), id: \.offset) { col, n in
                if n > 0 {
                    Text("ほか\(n)件")
                        .font(.app(min(9, size), weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: max(0, colW - 2), height: barH)
                        .offset(x: colW * CGFloat(col) + 1, y: CGFloat(WeekContent.maxLanes - 1) * (barH + laneGap))
                }
            }
            ForEach(content.bars.filter { !$0.link }) { b in
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

    /// 開始から締切までを 1 本につないだもの(カレンダーの月表示と同じ)。両端が矢印形のタグで、間は点線。
    /// 週をまたぐときは、この週にある側のタグだけを出して、点線は、週の端まで続ける
    private func linkBar(_ b: WeekBar, colW: CGFloat, size: CGFloat) -> some View {
        let width = max(0, colW * CGFloat(b.span) - 2)
        let tagW = max(0, colW - 2)
        let gap: CGFloat = 4
        let x1 = b.showsStart ? tagW + gap : 2
        let x2 = b.showsDue ? width - tagW - gap : width - 2
        return ZStack(alignment: .topLeading) {
            if x2 > x1 {
                TaskDots.path(x1: x1, x2: x2, y: barH / 2)
                    .fill(Color(hex: b.color))
            }
            if b.showsStart { tag(b, isStart: true, width: tagW, size: size) }
            if b.showsDue { tag(b, isStart: false, width: tagW, size: size).offset(x: width - tagW) }
        }
        .frame(width: width, height: barH, alignment: .topLeading)
        .offset(x: colW * CGFloat(b.col) + 1, y: CGFloat(b.lane) * (barH + laneGap))
    }

    private func tag(_ b: WeekBar, isStart: Bool, width: CGFloat, size: CGFloat) -> some View {
        Text(b.text).font(.bar(size, weight: .bold)).lineLimit(1)
            .padding(.leading, isStart ? 2 : 6)
            .padding(.trailing, isStart ? 6 : 2)
            .frame(width: width, height: barH, alignment: .leading)
            .clipped()
            .foregroundStyle(EventColor.text(b.color))
            .background { barBackground(WeekBar(id: b.id, col: b.col, span: 1, lane: b.lane, text: b.text, color: b.color,
                                                showsTime: false, taskStart: isStart)) }
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
