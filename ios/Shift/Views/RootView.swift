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
    @State private var paydayTarget: PaydayTarget?
    @State private var dragX: CGFloat = 0
    @State private var pagerWidth: CGFloat = 0
    @State private var lockFrames: [CGRect] = []
    @State private var dragStart: CGPoint?
    @State private var dragBlocked = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            pager
            UnplacedArea(anchor: anchor, onSelectEvent: edit)
        }
        .task(id: Rules.ymd(anchor).year) { await holidays.load(around: Rules.ymd(anchor).year) }
        .sheet(item: $editing) { EventEditor(original: $0.event, isNew: $0.isNew) }
        .sheet(item: $paydayTarget) { PaydaySheet(date: $0.date) }
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
                Button { slide(-1, width: pagerWidth) } label: { Image(systemName: "chevron.left") }
                Text(title).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                Button { slide(1, width: pagerWidth) } label: { Image(systemName: "chevron.right") }
                Spacer(minLength: 0)
                Button { addUnplaced() } label: {
                    Text("＋ 予定追加")
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
                Button { toggleSummary() } label: {
                    Text("週計")
                        .font(.caption.weight(.medium))
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
                        .font(.title3)
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
        GeometryReader { geo in
            let w = geo.size.width
            HStack(spacing: 0) {
                ForEach([-1, 0, 1], id: \.self) { k in
                    page(offset: k)
                        .frame(width: w, height: geo.size.height)
                        .clipped()
                }
            }
            .id(mode)
            .transition(.opacity)
            .frame(width: w * 3, alignment: .leading)
            .offset(x: -w + dragX)
            .clipped()
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 16, coordinateSpace: .named("pager"))
                    .onChanged { v in
                        if dragStart != v.startLocation {
                            dragStart = v.startLocation
                            dragBlocked = lockFrames.contains { $0.contains(v.startLocation) }
                        }
                        guard !dragBlocked else { return }
                        guard abs(v.translation.width) > abs(v.translation.height) else { return }
                        dragX = v.translation.width
                    }
                    .onEnded { v in
                        let wasBlocked = dragBlocked
                        dragStart = nil
                        dragBlocked = false
                        guard !wasBlocked else { return }
                        let dx = v.translation.width
                        let horizontal = abs(dx) > abs(v.translation.height)
                        if horizontal && (abs(dx) > w * 0.25 || abs(v.predictedEndTranslation.width) > w * 0.5) {
                            slide(dx < 0 ? 1 : -1, width: w)
                        } else {
                            withAnimation(.snappy(duration: 0.25)) { dragX = 0 }
                        }
                    })
            .onAppear { pagerWidth = w }
            .onChange(of: w) { _, new in pagerWidth = new }
        }
        .coordinateSpace(name: "pager")
        .onPreferenceChange(ScrollLockFramesKey.self) { lockFrames = $0 }
    }

    @ViewBuilder
    private func page(offset k: Int) -> some View {
        switch mode {
        case .month:
            MonthView(anchor: Rules.addMonths(anchor, k), startMonday: startMonday, summaryOn: summaryOn, onSelectDay: addEvent, onSelectEvent: edit, onDropEvent: drop, onSelectPayday: { paydayTarget = PaydayTarget(date: $0) })
        case .week:
            WeekView(anchor: Rules.addDays(anchor, 7 * k), startMonday: startMonday, summaryOn: summaryOn, onSelectDay: addEvent, onSelectEvent: edit, onDropEvent: drop, onSelectPayday: { paydayTarget = PaydayTarget(date: $0) })
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

    /// direction: +1 = 次の期間 (左へスライド), -1 = 前の期間
    private func slide(_ direction: Int, width: CGFloat) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let newAnchor = mode == .month ? Rules.addMonths(anchor, direction) : Rules.addDays(anchor, 7 * direction)
        withAnimation(.snappy(duration: 0.25), completionCriteria: .logicallyComplete) {
            dragX = direction > 0 ? -width : width
        } completion: {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                anchor = newAnchor
                dragX = 0
            }
        }
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
