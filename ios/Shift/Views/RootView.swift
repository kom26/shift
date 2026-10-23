import SwiftUI
import UIKit

enum CalendarMode: String { case week, month }

struct EditorTarget: Identifiable {
    let event: ShiftEvent
    let isNew: Bool
    var id: String { event.id }
}

struct RootView: View {
    @Environment(Store.self) private var store
    @Environment(Holidays.self) private var holidays
    @AppStorage("mode") private var mode: CalendarMode = .week
    @AppStorage("startMonday") private var startMonday = false
    @AppStorage("showSummary") private var showSummary = 0   // 0 なし / 1 週計 / 2 月計

    @State private var anchor = Rules.today()
    @State private var editing: EditorTarget?
    @State private var showFilter = false
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Group {
                switch mode {
                case .month:
                    MonthView(anchor: anchor, startMonday: startMonday, onSelectDay: addEvent, onSelectEvent: edit, onDropEvent: drop)
                case .week:
                    WeekView(anchor: anchor, startMonday: startMonday, onSelectDay: addEvent, onSelectEvent: edit, onDropEvent: drop)
                }
            }
            .id(mode)
            .transition(.opacity)
            .contentShape(Rectangle())
            .simultaneousGesture(swipe)
            if showSummary > 0 {
                SummaryBar(label: summary.label, totals: summary.totals)
            }
            UnplacedArea(anchor: anchor, onSelectEvent: edit)
        }
        .task(id: Rules.ymd(anchor).year) { await holidays.load(around: Rules.ymd(anchor).year) }
        .sheet(item: $editing) { EventEditor(original: $0.event, isNew: $0.isNew) }
        .sheet(isPresented: $showFilter) { FilterSheet() }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Button { step(-1) } label: { Image(systemName: "chevron.left") }
                Text(title).font(.headline).frame(maxWidth: .infinity)
                Button { step(1) } label: { Image(systemName: "chevron.right") }
            }
            HStack(spacing: 12) {
                Picker("表示", selection: $mode.animation(.snappy)) {
                    Text("週").tag(CalendarMode.week)
                    Text("月").tag(CalendarMode.month)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
                Button("今日") { withAnimation(.snappy) { anchor = Rules.today() } }
                    .font(.subheadline)
                Spacer()
                Button { showSummary = (showSummary + 1) % 3 } label: {
                    Text(["集計", "週計", "月計"][showSummary])
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .overlay(Capsule().stroke(showSummary > 0 ? Color.accentColor : Color.secondary.opacity(0.4)))
                }
                Button { showFilter = true } label: {
                    Image(systemName: store.checkedColors.isEmpty
                          ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                Button { addEvent(on: anchor) } label: { Image(systemName: "plus.circle.fill") }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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

    private var summary: (label: String, totals: [ColorTotal]) {
        if showSummary == 2 {
            let b = Rules.monthBounds(of: anchor)
            return ("月計", store.totals(from: b.first, to: b.last))
        }
        let s = Rules.weekStart(of: anchor, startMonday: startMonday)
        return ("週計", store.totals(from: s, to: Rules.addDays(s, 6)))
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 30).onEnded { v in
            guard abs(v.translation.width) > 60, abs(v.translation.width) > abs(v.translation.height) * 1.5 else { return }
            step(v.translation.width < 0 ? 1 : -1)
        }
    }

    private func step(_ n: Int) {
        withAnimation(.snappy) {
            anchor = mode == .month ? Rules.addMonths(anchor, n) : Rules.addDays(anchor, 7 * n)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func addEvent(on date: String) {
        editing = EditorTarget(event: .new(on: date), isNew: true)
    }

    private func edit(_ event: ShiftEvent) {
        editing = EditorTarget(event: event, isNew: false)
    }

    private func drop(id: String, on date: String) {
        withAnimation(.snappy) { store.place(id: id, on: date) }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}
