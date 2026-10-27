import SwiftUI
import UIKit

enum CalendarMode: String { case week, month }

struct EditorTarget: Identifiable {
    let event: ShiftEvent
    let isNew: Bool
    var favorite = false
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
    /// スタンプモード中のよく使う予定のID
    @State private var stampId: String?
    /// アラームのスタンプモード(時間を合わせて「セット」を押した状態)
    @State private var alarmStamp: AlarmPreset?
    @State private var toast: String?
    /// 日付なし予定の作成を始めたときの未配置の数。保存で増えたら未配置ページを開く
    @State private var unplacedCountOnCreate: Int?
    @State private var revealToken = 0
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            GeometryReader { geo in
                VStack(spacing: 0) {
                    if !unplacedCollapsed {
                        // 未配置エリアの高さは月(5週)基準で固定。6週の月でも週表示でも変えない
                        pager.frame(height: LayoutMath.monthCalendarHeight(available: geo.size.height, weeks: 5))
                    } else {
                        pager
                    }
                    UnplacedArea(anchor: anchor, selectedDate: selectedDate, startMonday: startMonday,
                                 fillHeight: true, revealUnplaced: revealToken, stampId: $stampId, alarmStamp: $alarmStamp, onSelectEvent: edit,
                                 onEditFavorite: { editing = EditorTarget(event: $0, isNew: false, favorite: true) },
                                 onNewFavorite: { editing = EditorTarget(event: .newUnplaced(), isNew: true, favorite: true) })
                }
            }
        }
        .task(id: Rules.ymd(anchor).year) { await holidays.load(around: Rules.ymd(anchor).year) }
        .task { await AlarmService.shared.refresh(store: store) }
        .onChange(of: scenePhase) { _, new in
            if new == .active { Task { await AlarmService.shared.refresh(store: store) } }
        }
        .overlay(alignment: .top) {
            if let toast {
                Text(toast)
                    .font(.app(13, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.8), in: Capsule())
                    .padding(.top, 60)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: anchor) { _, _ in selectedDate = nil }
        .onChange(of: mode) { _, _ in selectedDate = nil }
        .sheet(item: $editing, onDismiss: {
            if let n = unplacedCountOnCreate, store.unplacedEvents.count > n { revealToken += 1 }
            unplacedCountOnCreate = nil
        }) { EventEditor(original: $0.event, isNew: $0.isNew, favoriteMode: $0.favorite) }
        .sheet(item: $paydayTarget) { PaydaySheet(date: $0.date) }
        .sheet(item: $dayTarget) { t in
            DaySheet(date: t.date, onSelectEvent: { ev in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { edit(ev) }
            }, onAddEvent: {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { createEvent(on: t.date) }
            })
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showFilter) { FilterSheet() }
    }

    private var header: some View {
        VStack(spacing: 8) {
            if stampFavorite != nil || alarmStamp != nil {
                stampBanner
            } else {
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
                    Button { addFromHeader() } label: {
                        Text(addButtonTitle)
                            .font(.app(15, weight: .semibold))
                            .foregroundStyle(Theme.onAccent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Theme.accent, in: Capsule())
                    }
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

    private var stampFavorite: ShiftEvent? {
        stampId.flatMap { store.favorite(id: $0) }
    }

    /// スタンプモード中、ヘッダー1行目(設定・年月・予定追加)の代わりに出す帯
    @ViewBuilder
    private var stampBanner: some View {
        if stampFavorite != nil || alarmStamp != nil {
            HStack(spacing: 8) {
                Text(stampBannerText)
                    .font(.app(12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Button { withAnimation(.snappy) { stampId = nil; alarmStamp = nil } } label: {
                    Text("完了")
                        .font(.app(12, weight: .bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.25), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 10))
        }
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
            MonthView(anchor: Rules.addMonths(anchor, k), startMonday: startMonday, summaryOn: summaryOn, selectedDate: selectedDate, onSelectDay: tapDay, onSelectEvent: edit, onDropEvent: drop, onSelectPayday: { paydayTarget = PaydayTarget(date: $0) }, onLongPressDay: longPressDay)
        case .week:
            WeekView(anchor: Rules.addDays(anchor, 7 * k), startMonday: startMonday, summaryOn: summaryOn, selectedDate: selectedDate, onSelectDay: tapDay, onSelectEvent: edit, onDropEvent: drop, onSelectPayday: { paydayTarget = PaydayTarget(date: $0) }, onLongPressDay: longPressDay)
        }
    }

    /// 週計を切り替えると未配置エリアを必ず折りたたむ(自動では開かない)
    private func toggleSummary() {
        withAnimation(.snappy) {
            summaryOn.toggle()
        }
    }

    private var stampBannerText: String {
        if let fav = stampFavorite {
            let time = Rules.timeLabel(fav)
            return "「\(fav.title)\(time.isEmpty ? "" : " " + time)」を置く日をタップ"
        }
        if let spec = alarmStamp { return "⏰ \(spec.label) をセットする日をタップ" }
        return ""
    }

    private func showToast(_ text: String) {
        withAnimation(.snappy) { toast = text }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            withAnimation(.snappy) { if toast == text { toast = nil } }
        }
    }

    /// アラームのスタンプ: 日付のタップでセット、同じ日にもう一度タップで解除
    private func toggleAlarm(_ spec: AlarmPreset, on date: String) {
        Task { @MainActor in
            let r = await AlarmService.shared.toggle(spec: spec, on: date, store: store)
            switch r {
            case .set: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            case .removed: UIImpactFeedbackGenerator(style: .light).impactOccurred()
            case .noShift:
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                showToast("この日には時刻のあるシフトがありません")
            case .past:
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                showToast("鳴る時刻を過ぎています")
            case .denied:
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                showToast("設定アプリでアラームを許可してください")
            case .unsupported:
                showToast("アラームは iOS 26 以降で使えます")
            case .failed:
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                showToast("アラームをセットできませんでした")
            }
        }
    }

    private var addButtonTitle: String {
        guard let d = selectedDate else { return "＋ 予定追加" }
        return "＋ \(Rules.ymd(d).day)日に追加"
    }

    /// 日付セルのタップ: スタンプ中は配置、そうでなければ選択。選択中の日をもう一度タップで一覧
    private func tapDay(_ date: String) {
        if alarmStamp != nil || stampId != nil {
            addEvent(on: date)
        } else if selectedDate == date {
            dayTarget = DayTarget(date: date)
        } else {
            selectedDate = date
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    /// 日付セルの長押し: その日の予定を追加(スタンプ中は何もしない)
    private func longPressDay(_ date: String) {
        guard alarmStamp == nil, stampId == nil else { return }
        createEvent(on: date)
    }

    private func createEvent(on date: String) {
        selectedDate = date
        editing = EditorTarget(event: .new(on: date), isNew: true)
    }

    private func addFromHeader() {
        if let d = selectedDate { createEvent(on: d) } else { addUnplaced() }
    }

    private func addEvent(on date: String) {
        if let spec = alarmStamp {
            toggleAlarm(spec, on: date)
            return
        }
        if let id = stampId {
            // スタンプモード: 日付のタップで配置、同じ日にもう一度タップで削除
            if let r = store.stampToggle(favoriteId: id, on: date) {
                UIImpactFeedbackGenerator(style: r == .placed ? .medium : .light).impactOccurred()
            } else {
                stampId = nil
            }
            return
        }
        selectedDate = date
        editing = EditorTarget(event: .new(on: date), isNew: true)
    }

    private func addUnplaced() {
        unplacedCountOnCreate = store.unplacedEvents.count
        editing = EditorTarget(event: .newUnplaced(), isNew: true)
    }

    private func edit(_ event: ShiftEvent) {
        editing = EditorTarget(event: event, isNew: false)
    }

    private func drop(id: String, on date: String) {
        if id.hasPrefix(Store.favoritePrefix) {
            withAnimation(.snappy) { store.stampCopy(favoriteId: String(id.dropFirst(Store.favoritePrefix.count)), on: date) }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            return
        }
        withAnimation(.snappy) { store.place(id: id, on: date) }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}
