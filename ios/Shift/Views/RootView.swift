import SwiftUI
import UIKit

enum CalendarMode: String { case week, month }

struct EditorTarget: Identifiable {
    let event: ShiftEvent
    let isNew: Bool
    var id: String { event.id }
}

struct PaydayTarget: Identifiable {
    let date: String
    var id: String { date }
}

struct DayTarget: Identifiable {
    let date: String
    var id: String { date }
}

struct RootView: View {
    @Environment(Store.self) private var store
    @Environment(Holidays.self) private var holidays
    @AppStorage("mode") private var mode: CalendarMode = .week
    @AppStorage("startMonday") private var startMonday = false
    @AppStorage("summaryOn") private var summaryOn = false
    @AppStorage("unplacedCollapsed") private var unplacedCollapsed = false

    @State private var anchor = Rules.today()
    @State private var editing: EditorTarget?
    @State private var showSettings = false
    @State private var showFilter = false
    @State private var paydayTarget: PaydayTarget?
    @State private var dayTarget: DayTarget?
    @State private var pagerCommand: PagerCommand?
    @State private var selectedDate: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            GeometryReader { geo in
                VStack(spacing: 0) {
                    if mode == .month && !unplacedCollapsed {
                        pager.frame(height: LayoutMath.monthCalendarHeight(available: geo.size.height, weeks: monthWeekCount))
                    } else {
                        pager
                    }
                    UnplacedArea(anchor: anchor, selectedDate: selectedDate, startMonday: startMonday,
                                 fillHeight: mode == .month, onSelectEvent: edit)
                }
            }
        }
        .task(id: Rules.ymd(anchor).year) { await holidays.load(around: Rules.ymd(anchor).year) }
        .sheet(item: $editing) { EventEditor(original: $0.event, isNew: $0.isNew) }
        .sheet(item: $paydayTarget) { PaydaySheet(date: $0.date) }
        .sheet(item: $dayTarget) { t in
            DaySheet(date: t.date, onSelectEvent: { ev in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { edit(ev) }
            })
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showFilter) { FilterSheet() }
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape").font(.title3)
                        .padding(.horizontal, 6)
                        .frame(minHeight: 36)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("設定")
                Spacer(minLength: 0)
                Button { pagerCommand = PagerCommand(direction: -1, id: UUID()) } label: { Image(systemName: "chevron.left") }
                Text(title).font(.app(17, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                Button { pagerCommand = PagerCommand(direction: 1, id: UUID()) } label: { Image(systemName: "chevron.right") }
                Spacer(minLength: 0)
                Button { addUnplaced() } label: {
                    Text("＋ 予定追加")
                        .font(.app(15, weight: .semibold))
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Theme.accent, in: Capsule())
                }
            }
            HStack(spacing: 10) {
                Picker("表示", selection: $mode.animation(.snappy)) {
                    Text("週").tag(CalendarMode.week)
                    Text("月").tag(CalendarMode.month)
                }
                .pickerStyle(.segmented)
                .frame(width: 110)
                Button { withAnimation(.snappy) { anchor = Rules.today() } } label: {
                    Text("今日").font(.app(15)).padding(.horizontal, 6).frame(minHeight: 36).contentShape(Rectangle())
                }
                Spacer(minLength: 0)
                Button { toggleSummary() } label: {
                    Text("週計")
                        .font(.app(12, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(summaryOn ? Theme.accentSoft : Color.clear, in: Capsule())
                        .overlay(Capsule().stroke(summaryOn ? Theme.accent : Color.secondary.opacity(0.4)))
                        .frame(minHeight: 36)
                        .contentShape(Rectangle())
                }
                Button { showFilter = true } label: {
                    Image(systemName: store.checkedWorkplaces.isEmpty
                          ? "line.3.horizontal.decrease.circle"
                          : "line.3.horizontal.decrease.circle.fill")
                        .font(.app(20))
                        .foregroundStyle(store.checkedWorkplaces.isEmpty ? Color.primary : Theme.accent)
                        .frame(minWidth: 36, minHeight: 36)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("職場フィルタ")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var monthWeekCount: Int {
        let p = Rules.ymd(anchor)
        return Rules.monthGrid(year: p.year, month: p.month, startMonday: startMonday).count
    }

    private var title: String {
        if mode == .month {
            let p = Rules.ymd(anchor)
            return "\(p.year)年\(p.month)月"
        }
        let s = Rules.weekStart(of: anchor, startMonday: startMonday)
        let sp = Rules.ymd(s), ep = Rules.ymd(Rules.addDays(s, 6))
        return sp.month == ep.month
            ? "\(sp.year)年\(sp.month)月\(sp.day)〜\(ep.day)日"
            : "\(sp.month)月\(sp.day)日〜\(ep.month)月\(ep.day)日"
    }

    private var pager: some View {
        PagerView(prev: page(offset: -1), current: page(offset: 0), next: page(offset: 1),
                  command: $pagerCommand,
                  onCommit: { dir in
                      anchor = mode == .month ? Rules.addMonths(anchor, dir) : Rules.addDays(anchor, 7 * dir)
                  })
            .id(mode)
            .transition(.opacity)
    }

    @ViewBuilder
    private func page(offset k: Int) -> some View {
        switch mode {
        case .month:
            MonthView(anchor: Rules.addMonths(anchor, k), startMonday: startMonday, summaryOn: summaryOn, selectedDate: selectedDate, onSelectDay: addEvent, onSelectEvent: edit, onDropEvent: drop, onSelectPayday: { paydayTarget = PaydayTarget(date: $0) }, onLongPressDay: { dayTarget = DayTarget(date: $0) })
        case .week:
            WeekView(anchor: Rules.addDays(anchor, 7 * k), startMonday: startMonday, summaryOn: summaryOn, selectedDate: selectedDate, onSelectDay: addEvent, onSelectEvent: edit, onDropEvent: drop, onSelectPayday: { paydayTarget = PaydayTarget(date: $0) }, onLongPressDay: { dayTarget = DayTarget(date: $0) })
        }
    }

    /// 週計を切り替えると未配置エリアを必ず折りたたむ(自動では開かない)
    private func toggleSummary() {
        withAnimation(.snappy) {
            summaryOn.toggle()
            unplacedCollapsed = true
        }
    }

    private func addEvent(on date: String) {
        selectedDate = date
        editing = EditorTarget(event: .new(on: date), isNew: true)
    }

    private func addUnplaced() {
        editing = EditorTarget(event: .newUnplaced(), isNew: true)
    }

    private func edit(_ event: ShiftEvent) {
        editing = EditorTarget(event: event, isNew: false)
    }

    private func drop(id: String, on date: String) {
        withAnimation(.snappy) { store.place(id: id, on: date) }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}
