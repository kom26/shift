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
    @AppStorage("summaryOn") private var summaryOn = false
    @AppStorage("unplacedCollapsed") private var unplacedCollapsed = false

    @State private var anchor = Rules.today()
    @State private var collapsedBeforeSummary = false
    @State private var editing: EditorTarget?
    @State private var showSettings = false
    @State private var showFilter = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Group {
                switch mode {
                case .month:
                    MonthView(anchor: anchor, startMonday: startMonday, summaryOn: summaryOn, onSelectDay: addEvent, onSelectEvent: edit, onDropEvent: drop)
                case .week:
                    WeekView(anchor: anchor, startMonday: startMonday, summaryOn: summaryOn, onSelectDay: addEvent, onSelectEvent: edit, onDropEvent: drop)
                }
            }
            .id(mode)
            .transition(.opacity)
            .contentShape(Rectangle())
            .simultaneousGesture(swipe)
            UnplacedArea(anchor: anchor, onSelectEvent: edit)
        }
        .task(id: Rules.ymd(anchor).year) { await holidays.load(around: Rules.ymd(anchor).year) }
        .sheet(item: $editing) { EventEditor(original: $0.event, isNew: $0.isNew) }
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
                Button { step(-1) } label: { Image(systemName: "chevron.left") }
                Text(title).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                Button { step(1) } label: { Image(systemName: "chevron.right") }
                Spacer(minLength: 0)
                Button { addUnplaced() } label: {
                    Text("＋ 追加")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
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
                    Text("今日").font(.subheadline).padding(.horizontal, 6).frame(minHeight: 36).contentShape(Rectangle())
                }
                Spacer(minLength: 0)
                Button { showFilter = true } label: {
                    Image(systemName: store.checkedColors.isEmpty
                          ? "line.3.horizontal.decrease.circle"
                          : "line.3.horizontal.decrease.circle.fill")
                        .font(.title3)
                        .foregroundStyle(store.checkedColors.isEmpty ? Color.primary : Theme.accent)
                        .frame(minWidth: 36, minHeight: 36)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("色フィルタ")
                Button { toggleSummary() } label: {
                    Text("集計")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(summaryOn ? Theme.accentSoft : Color.clear, in: Capsule())
                        .overlay(Capsule().stroke(summaryOn ? Theme.accent : Color.secondary.opacity(0.4)))
                        .frame(minHeight: 36)
                        .contentShape(Rectangle())
                }
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

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 30).onEnded { v in
            guard abs(v.translation.width) > 60, abs(v.translation.width) > abs(v.translation.height) * 1.5 else { return }
            step(v.translation.width < 0 ? 1 : -1)
        }
    }

    /// 集計をオンにすると未配置エリアを折りたたみ、オフにすると元の開閉状態に戻す
    private func toggleSummary() {
        withAnimation(.snappy) {
            if summaryOn {
                summaryOn = false
                unplacedCollapsed = collapsedBeforeSummary
            } else {
                collapsedBeforeSummary = unplacedCollapsed
                summaryOn = true
                unplacedCollapsed = true
            }
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
