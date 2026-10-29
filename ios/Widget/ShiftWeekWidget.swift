import SwiftUI
import WidgetKit
import AppIntents

struct WeekEntry: TimelineEntry {
    let date: Date
    let content: WeekContent
    let offset: Int
}

struct WeekProvider: TimelineProvider {
    private func entry(now: Date = Date()) -> WeekEntry {
        let today = Rules.today()
        let offset = WidgetOffset(key: "week").current(today: today)
        let source = WidgetSource.load()
        let content = source.weekContent(containing: Rules.addDays(today, 7 * offset), today: today)
        return WeekEntry(date: now, content: content, offset: offset)
    }

    func placeholder(in context: Context) -> WeekEntry { entry() }

    func getSnapshot(in context: Context, completion: @escaping (WeekEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeekEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .after(nextMidnight())))
    }
}

struct ShiftWeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetBridge.weekKind, provider: WeekProvider()) { entry in
            MediumWeekView(content: entry.content, offset: entry.offset)
                .containerBackground(Color(.systemBackground), for: .widget)
        }
        .configurationDisplayName("1週間")
        .description("今日を含む1週間の予定と、週の労働時間・見込み給料を見られます。")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

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

    private var footer: some View {
        HStack {
            Text("労働 ").font(.app(10)).foregroundStyle(.secondary)
                + Text(content.hours).font(.app(10, weight: .semibold))
            Spacer()
            Text("見込み給料 ").font(.app(10)).foregroundStyle(.secondary)
                + Text(content.pay).font(.app(10, weight: .semibold))
        }
        .monospacedDigit()
        .frame(height: 14)
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
                .padding(.horizontal, 2)
                .frame(width: max(0, colW * CGFloat(b.span) - 2), height: barH, alignment: .leading)
                .clipped()
                .foregroundStyle(EventColor.text(b.color))
                .background(EventColor.fill(b.color), in: RoundedRectangle(cornerRadius: 4))
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 4))
                .offset(x: colW * CGFloat(b.col) + 1, y: CGFloat(b.lane) * (barH + laneGap))
            }
        }
    }

    /// 日付ごとのタップ領域。その日の予定一覧をアプリで開く
    private func dayLinks(colW: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { i in
                Link(destination: URL(string: "shiftpalette://day/\(content.days[i])") ?? URL(fileURLWithPath: "/")) {
                    Color.clear.contentShape(Rectangle())
                }
                .frame(width: colW, height: height)
            }
        }
    }
}
