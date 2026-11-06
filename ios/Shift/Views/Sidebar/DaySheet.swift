import SwiftUI

struct DaySheet: View {
    @Environment(Store.self) private var store
    @Environment(Holidays.self) private var holidays
    @Environment(\.dismiss) private var dismiss
    @Environment(SharedViewState.self) private var shared

    /// 表示中の日。横にスワイプすると前日・翌日に移る
    @State private var date: String
    /// スワイプで、新しい日が右から(翌日)・左から(前日)入ってくる向き
    @State private var forward = true
    /// 詳細を開いている記念日・誕生日
    @State private var annivId: String?
    /// 共有カレンダーなど、見るだけのときは false(予定追加のボタンを出さない)
    let canAdd: Bool
    let onSelectEvent: (ShiftEvent) -> Void
    let onSelectPayday: (String) -> Void
    let onAddEvent: (String) -> Void

    init(date: String, canAdd: Bool = true, onSelectEvent: @escaping (ShiftEvent) -> Void,
         onSelectPayday: @escaping (String) -> Void = { _ in }, onAddEvent: @escaping (String) -> Void = { _ in }) {
        _date = State(initialValue: date)
        self.canAdd = canAdd
        self.onSelectEvent = onSelectEvent
        self.onSelectPayday = onSelectPayday
        self.onAddEvent = onAddEvent
    }

    private var dateText: String {
        let p = Rules.ymd(date)
        let wd = Rules.weekdayLabels(startMonday: false)[Rules.weekday(date)]
        return "\(p.year)年\(p.month)月\(p.day)日 (\(wd))"
    }

    var body: some View {
        let summary = store.daySummary(date: date, isHoliday: { holidays.name(on: $0) != nil })
        let annivs = store.anniversaries(on: date)
        NavigationStack {
            VStack(spacing: 0) {
                dayContent(summary: summary, annivs: annivs)
                    .id(date)
                    .transition(.asymmetric(
                        insertion: .move(edge: forward ? .trailing : .leading),
                        removal: .move(edge: forward ? .leading : .trailing)))
            }
            .clipped()
            .simultaneousGesture(daySwipe)
            .navigationDestination(item: $annivId) { AnniversaryDetail(id: $0, asOf: date) }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 右上の ⊕ で、この日に予定を追加する(閉じるのは、画面を下げる)
                if canAdd {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            dismiss()
                            onAddEvent(date)
                        } label: { Image(systemName: "plus") }
                            .accessibilityLabel("この日に予定を追加")
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color(.systemBackground))
        .presentationDragIndicator(.visible)
    }

    /// 横にはっきり動かしたときだけ、前日・翌日へ(縦のスクロールとは分ける)
    private var daySwipe: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { v in
                guard abs(v.translation.width) > 60, abs(v.translation.width) > abs(v.translation.height) * 1.5 else { return }
                move(by: v.translation.width < 0 ? 1 : -1)
            }
    }

    private func move(by days: Int) {
        forward = days > 0
        withAnimation(.snappy) { date = Rules.addDays(date, days) }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    @ViewBuilder
    private func dayContent(summary: DaySummary, annivs: [Anniversary]) -> some View {
        VStack(spacing: 0) {
                Text(dateText)
                    .font(.app(14))
                    .foregroundStyle(Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color(.secondarySystemBackground))
                badges(summary)
                if summary.events.isEmpty && annivs.isEmpty {
                    Spacer()
                    Text("予定はありません")
                        .foregroundStyle(Color.secondary)
                    Spacer()
                } else {
                    List {
                        // 記念日・誕生日(タップで詳細。メモもそこで見られる)
                        ForEach(annivs) { a in
                            // 横にスワイプして指を離したときに開かないよう、ボタンではなく「タップ」だけで開く
                            HStack(spacing: 10) {
                                    AnniversaryIcon(icon: a.icon, color: a.color, size: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(a.name).font(.app(17))
                                        if !a.memo.isEmpty {
                                            Text(a.memo).font(.app(12)).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                    }
                                    Spacer(minLength: 8)
                                    if let e = a.elapsedText(asOf: date) {
                                        Text(e).font(.app(15, weight: .semibold).monospacedDigit())
                                            .foregroundStyle(Color(hex: a.color))
                                    }
                                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { annivId = a.id }
                            .accessibilityAddTraits(.isButton)
                        }
                        ForEach(summary.events) { row in
                            // 横にスワイプして指を離したときに開かないよう、ボタンではなく「タップ」だけで開く
                            eventRow(row)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    dismiss()
                                    onSelectEvent(row.event)
                                }
                                .accessibilityAddTraits(.isButton)
                        }
                    }
                    .listStyle(.plain)
                }
        }
    }

    @ViewBuilder
    private func badges(_ summary: DaySummary) -> some View {
        let alarms = store.alarmFireMinutes(on: date).sorted()
        if !summary.paydays.isEmpty || !alarms.isEmpty {
            HStack(spacing: 6) {
                ForEach(summary.paydays) { r in
                    Button {
                        dismiss()
                        onSelectPayday(date)
                    } label: {
                    Text("給料日 \(Money.yen(r.amount))")
                        .font(.app(11, weight: .semibold))
                        .foregroundStyle(Theme.payText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Theme.payFill, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                ForEach(alarms, id: \.self) { m in
                    Label(String(format: "%d:%02d", m / 60, m % 60), systemImage: "bell.fill")
                        .font(.app(11, weight: .semibold))
                        .foregroundStyle(Theme.alarm)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Theme.alarm.opacity(0.16), in: Capsule())
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func paydayRow(_ r: Store.PaymentRow) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text("給料日")
                .font(.app(13, weight: .bold))
                .foregroundStyle(Theme.payText)
                .frame(width: 64, alignment: .trailing)
            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.payText.opacity(0.7))
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(Money.yen(r.amount))
                    .font(.app(17, weight: .bold))
                    .foregroundStyle(Theme.payText)
                Text(r.workplace.name)
                    .font(.app(17))
                    .foregroundStyle(Color.primary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private func eventRow(_ row: DayEventRow) -> some View {
        let ev = row.event
        return HStack(alignment: .center, spacing: 8) {
            timeColumn(row)
                .frame(width: 64, alignment: .trailing)
            RoundedRectangle(cornerRadius: 2)
                .fill(EventColor.fill(ev.color))
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(ev.title)
                    .font(.app(17))
                    .foregroundStyle(Color.primary)
                if !ev.memo.isEmpty {
                    Text(ev.memo)
                        .font(.app(12))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            // 共有カレンダーでは、誰の予定かをアバターで見せる(共有カレンダーの中で作った予定は、みんなのものなので出さない)
            if shared.event(ev.id)?.isCalendarOwned == false, let o = shared.owner(of: ev.id) {
                UserAvatar(uid: o.uid, name: o.name, avatar: o.avatar, size: 28)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func timeColumn(_ row: DayEventRow) -> some View {
        let ev = row.event
        if row.isAllDay {
            Text("終日")
                .font(.app(16))
                .foregroundStyle(Color.primary)
        } else if row.isContinuation {
            VStack(alignment: .trailing, spacing: 2) {
                Text("前日から")
                    .font(.app(11))
                    .foregroundStyle(Color.secondary)
                if let e = ev.endTime {
                    Text(e)
                        .font(.app(14).monospacedDigit())
                        .foregroundStyle(Color.secondary)
                }
            }
        } else {
            VStack(alignment: .trailing, spacing: 2) {
                Text(ev.startTime ?? "")
                    .font(.app(16).monospacedDigit())
                    .foregroundStyle(Color.primary)
                if let e = ev.endTime {
                    Text(e)
                        .font(.app(14).monospacedDigit())
                        .foregroundStyle(Color.secondary)
                }
            }
        }
    }
}
