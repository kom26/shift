import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct WeekView: View {
    @Environment(Store.self) private var store
    @Environment(\.calendarBackground) private var calBg
    @Environment(Holidays.self) private var holidays
    let anchor: String
    let startMonday: Bool
    let summaryOn: Bool
    let selectedDate: String?
    let onSelectDay: (String) -> Void
    let onSelectEvent: (ShiftEvent) -> Void
    /// 予定バーのタップ(タップした日つき)
    let onTapEvent: (ShiftEvent, String) -> Void
    let onDropEvent: (String, String) -> Void
    let onSelectPayday: (String) -> Void
    let onLongPressDay: (String) -> Void

    @AppStorage("conflictWarningOn") private var conflictWarningOn = true
    @Environment(\.isSharedView) private var isSharedView
    @AppStorage("conflictGapMinutes") private var conflictGapMinutes = 0
    @AppStorage(BarFontSize.weekKey) private var fontDelta = 0.0
    @State private var dropTarget: String?
    @Environment(\.isStamping) private var isStamping

    private let timeW: CGFloat = 22
    private let barH: CGFloat = 20

    var body: some View {
        let start = Rules.weekStart(of: anchor, startMonday: startMonday)
        let days = (0..<7).map { Rules.addDays(start, $0) }
        let conflictDays: Set<String> = conflictWarningOn && !isSharedView ? Conflicts.days(events: store.events, minGapMinutes: conflictGapMinutes) : []
        let allDayRows = SpanLayout.rows(events: store.visibleEvents.filter(\.allDay) + store.taskMarkers(timelessOnly: true), weekCells: days.map { Optional($0) })
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Color.clear.frame(width: timeW, height: 0)
                    ForEach(days, id: \.self) { header($0, conflict: conflictDays.contains($0)) }
                }
                allDayRow(days: days, rows: allDayRows)
                Divider()
                grid(days, conflictDays: conflictDays)
            }
            // 選んだ日の紫の枠は、日付から 24 時のところまで、縦長に囲む
            .overlay { selectionFrame(days) }
            let b = Rules.monthBounds(of: anchor)
            let monthTotals = store.totals(from: b.first, to: b.last, isHoliday: { holidays.name(on: $0) != nil })
            if summaryOn && !isSharedView {
                Divider()
                SummaryStrip(label: "週計", totals: store.totals(from: days[0], to: days[6], isHoliday: { holidays.name(on: $0) != nil }, orderBy: monthTotals.map(\.key)), emptyText: "データなし",
                             fill: calBg, labelColor: Color.secondary)
                    .frame(height: 18)
            } else {
                Divider()
            }
        }
        .background { MonthWatermark(number: Rules.ymd(days[3]).month) }
    }

    private func header(_ ds: String, conflict: Bool) -> some View {
        let holiday = holidays.name(on: ds)
        let type = Rules.dayType(ds, isHoliday: holiday != nil)
        let isToday = ds == Rules.today()
        return VStack(spacing: 1) {
            Text(Rules.weekdayLabels(startMonday: false)[Rules.weekday(ds)])
                .font(.app(9))
                .foregroundStyle(type.color)
            Text("\(Rules.ymd(ds).day)")
                .font(.app(13, weight: .semibold))
                .foregroundStyle(isToday ? Theme.accent : (type == .normal ? Color.primary : type.color))
            Text(holiday ?? " ")
                .font(.app(9))
                .foregroundStyle(Theme.sunday)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .overlay(alignment: .topTrailing) {
            if store.hasPayday(on: ds) {
                PaydayCoinButton()
            }
        }
        .overlay(alignment: store.hasPayday(on: ds) ? .topLeading : .topTrailing) {
            let alarms = store.alarmCount(on: ds)
            if alarms > 0 {
                HStack(spacing: 1) {
                    Image(systemName: "bell.fill").font(.app(10))
                    if alarms > 1 { Text("+\(alarms - 1)").font(.app(9, weight: .bold)) }
                }
                .foregroundStyle(Theme.alarm)
                .padding(.top, 5)
                .padding(store.hasPayday(on: ds) ? .leading : .trailing, 5)
                .accessibilityLabel("アラーム \(alarms)件")
            }
        }
        .background(conflict ? Color.red.opacity(0.16) : (isToday ? Theme.accentSoft : Color.clear))
        // 日付の部分を押しても、その日を選べる
        .contentShape(Rectangle())
        .onTapGesture { onSelectDay(ds) }
    }

    /// 選んだ日の列を、日付から 24 時のところまで囲む枠
    private func selectionFrame(_ days: [String]) -> some View {
        GeometryReader { geo in
            if let sel = selectedDate, let i = days.firstIndex(of: sel) {
                let colW = (geo.size.width - timeW) / 7
                Rectangle()
                    .strokeBorder(Theme.accent, lineWidth: 1.5)
                    .frame(width: colW, height: geo.size.height)
                    .offset(x: timeW + colW * CGFloat(i))
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func allDayRow(days: [String], rows: [[BarSpan]]) -> some View {
        if rows.isEmpty {
            EmptyView()
        } else {
            GeometryReader { geo in
                let colW = (geo.size.width - timeW) / 7
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 0) {
                        Color.clear.frame(width: timeW)
                        ForEach(0..<7, id: \.self) { i in
                            (dropTarget == days[i] && !(dropMoved?.isTimedDrop ?? false) ? Theme.accentSoft : Color.clear)
                                .contentShape(Rectangle())
                                .onTapGesture { onSelectDay(days[i]) }
                                .onLongPressGesture(minimumDuration: 0.45) {
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    onLongPressDay(days[i])
                                }
                        }
                    }
                    SpanBars(rows: rows, colW: colW, barH: barH, leading: timeW,
                             onTap: { ev, col in onTapEvent(ev, days[min(6, max(0, col))]) }, onEdit: onSelectEvent)
                }
                .onDrop(of: [.plainText], delegate: EventDropDelegate(
                    resolve: { p in
                        guard colW > 0 else { return nil }
                        return storageDate(days[min(6, max(0, Int((p.x - timeW) / colW)))])
                    },
                    target: $dropTarget,
                    originKey: "allday",
                    cellRect: { p in
                        guard colW > 0 else { return CGRect(origin: p, size: .zero) }
                        let col = CGFloat(min(6, max(0, Int((p.x - timeW) / colW))))
                        return CGRect(x: timeW + col * colW, y: p.y, width: colW, height: 0)
                    },
                    onDrop: onDropEvent))
                .onGeometryChange(for: CGPoint.self) { $0.frame(in: .global).origin } action: {
                    DragState.shared.dropOrigins["allday"] = $0
                }
            }
            .frame(height: CGFloat(rows.count) * (barH + 2) + 4)
            .clipped()
        }
    }

    private func grid(_ days: [String], conflictDays: Set<String>) -> some View {
        GeometryReader { geo in
            let colW = (geo.size.width - timeW) / 7
            let H = geo.size.height
            let timed = store.visibleEvents.filter { !$0.allDay }
            ZStack(alignment: .topLeading) {
                ForEach(0..<48, id: \.self) { k in
                    Rectangle()
                        .fill(Color(.separator).opacity(k % 2 == 0 ? 0.5 : 0.2))
                        .frame(width: geo.size.width - timeW, height: 0.5)
                        .offset(x: timeW, y: H * CGFloat(k) / 48)
                }
                ForEach(1..<24, id: \.self) { h in
                    Text("\(h)")
                        .font(.app(8).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: timeW - 2, alignment: .trailing)
                        .offset(y: H * CGFloat(h) / 24 - 5)
                }
                ForEach(0..<7, id: \.self) { i in
                    let ds = days[i]
                    column(ds, events: timed, colW: colW, H: H)
                        .frame(width: colW, height: H, alignment: .topLeading)
                        .background(dropTarget == ds && !(dropMoved?.isTimedDrop ?? false) ? Theme.accentSoft : (conflictDays.contains(ds) ? Color.red.opacity(0.10) : Color.clear))
                        .overlay(alignment: .topLeading) { dropSegment(ds, colW: colW, H: H) }
                        .overlay(alignment: .leading) {
                            Rectangle().fill(Color(.separator).opacity(0.5)).frame(width: 0.5)
                        }
                        .onDrop(of: [.plainText], delegate: EventDropDelegate(
                            resolve: { _ in storageDate(ds) },
                            target: $dropTarget,
                            originKey: "col-" + ds,
                            cellRect: { p in CGRect(x: 0, y: p.y, width: colW, height: 0) },
                            onDrop: onDropEvent))
                        .onGeometryChange(for: CGPoint.self) { $0.frame(in: .global).origin } action: {
                            DragState.shared.dropOrigins["col-" + ds] = $0
                        }
                        .offset(x: timeW + colW * CGFloat(i))
                }
            }
        }
        .clipped()
    }

    /// 日をまたぐ予定・24:00以降に始まる予定は、つかんだ側の列(開始日から何日目か)を基準に置く。
    /// 指のある列につかんだセグメントが来るよう、保存上の開始日をその日数だけ前にずらして返す
    private func storageDate(_ ds: String) -> String {
        let k = DragState.shared.grabOffsetDays
        return k == 0 ? ds : Rules.addDays(ds, -k)
    }

    /// ドラッグ中の予定を dropTarget に置いたときの姿
    private var dropMoved: ShiftEvent? {
        // ドラッグ中は指のある列、離したあと(移動/コピーの選択中)は移動先の列に出す
        if let t = dropTarget, let id = DragState.shared.draggingId { return store.dropPreview(id: id, on: t) }
        if let id = DragState.shared.pendingId, let t = DragState.shared.pendingDate { return store.dropPreview(id: id, on: t) }
        return nil
    }

    /// 予定がハマる時間帯だけを点線と塗りで示す(他の予定と重なるなら赤)
    @ViewBuilder
    private func dropSegment(_ ds: String, colW: CGFloat, H: CGFloat) -> some View {
        if let m = dropMoved, m.isTimedDrop, let seg = Rules.timedSegment(m, on: ds) {
            let bad = DropCheck.overlaps(moved: m, others: store.events)
            let tint: Color = bad ? .red : Theme.accent
            let shape = RoundedRectangle(cornerRadius: 3)
            shape.fill(bad ? Color.red.opacity(0.22) : Theme.accentSoft)
                .overlay(shape.strokeBorder(tint, style: StrokeStyle(lineWidth: 2, dash: [4, 3])))
                .frame(width: max(0, colW - 2), height: H * CGFloat(seg.height))
                .offset(x: 1, y: H * CGFloat(seg.top))
                .allowsHitTesting(false)
        }
    }

    private func column(_ ds: String, events: [ShiftEvent], colW: CGFloat, H: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear.contentShape(Rectangle())
                .onTapGesture { onSelectDay(ds) }
                .onLongPressGesture(minimumDuration: 0.45) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onLongPressDay(ds)
                }
            // 時間が重なる予定は、横に分けて、どちらも見えるようにする
            let slots = TimedLanes.assign(events.compactMap { ev in
                Rules.timedSegment(ev, on: ds).map { TimedLanes.Item(id: ev.id, top: $0.top, bottom: $0.top + $0.height) }
            })
            ForEach(events) { ev in
                if let seg = Rules.timedSegment(ev, on: ds) {
                    let h = max(14, H * CGFloat(seg.height))
                    let slot = slots[ev.id] ?? TimedLanes.Slot(lane: 0, count: 1)
                    let laneW = max(0, colW - 2) / CGFloat(slot.count)
                    block(ev, h: h)
                        .frame(width: laneW, height: h)
                        .onTapGesture { onTapEvent(ev, ds) }
                        .eventDragSource(ev, grabOffsetDays: Rules.daysBetween(ev.startDate ?? ds, ds), onOpen: onSelectEvent)
                        .allowsHitTesting(!isStamping)
                        .offset(x: 1 + laneW * CGFloat(slot.lane), y: H * CGFloat(seg.top))
                }
            }
            // アラーム・開始・締切の印は、その時刻に線で出す。近い印は、通常の予定と同じように、列の幅を分け合う
            let markers = store.alarmFireMinutes(on: ds).map { WeekMarkerLayout.Item(kind: .bell, minutes: $0, color: nil) }
                + store.taskLines(on: ds).map { WeekMarkerLayout.Item(kind: $0.isStart ? .start : .due, minutes: $0.minutes, color: $0.task.color) }
            ForEach(Array(WeekMarkerLayout.layout(markers).enumerated()), id: \.offset) { _, slot in
                markerLine(slot, colW: colW, H: H)
            }
            if ds == Rules.today() {
                TimelineView(.everyMinute) { ctx in
                    let c = Calendar.current.dateComponents([.hour, .minute], from: ctx.date)
                    let mins = CGFloat((c.hour ?? 0) * 60 + (c.minute ?? 0))
                    ZStack(alignment: .topLeading) {
                        Rectangle().fill(Color.red).frame(width: colW, height: 2)
                        Circle().fill(Color.red).frame(width: 8, height: 8).offset(x: -4, y: -3)
                    }
                    .offset(y: H * mins / 1440 - 1)
                }
                .allowsHitTesting(false)
            }
        }
    }

    /// 時刻の印 1 つ。線の上に、印(ベル・再生・旗)だけを出す(開始・締切のタイトルは出さない)。
    /// 印と「+n」は、分け合った幅に収まるように、幅に合わせて小さくする
    private func markerLine(_ slot: WeekMarkerLayout.Slot, colW: CGFloat, H: CGFloat) -> some View {
        let w = colW / CGFloat(slot.count)
        let size = max(5, min(9, (w * 0.42).rounded(.down)))
        let plusSize = max(5, min(8, (w * 0.34).rounded(.down)))
        let tint = slot.color.map { Color(hex: $0) } ?? Theme.alarm
        let symbol: String
        switch slot.kind {
        case .bell: symbol = "bell.fill"
        case .start: symbol = "play.fill"
        case .due: symbol = "flag.fill"
        }
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(tint).frame(width: w, height: 2)
            HStack(spacing: 1) {
                Image(systemName: symbol).font(.system(size: size))
                if slot.extra > 0 {
                    Text("+\(slot.extra)").font(.system(size: plusSize, weight: .bold))
                }
            }
            .foregroundStyle(slot.color.map { EventColor.text($0) } ?? Theme.alarm)
            .frame(width: w, alignment: .leading)
            .lineLimit(1)
            .fixedSize(horizontal: false, vertical: true)
            .offset(x: 1, y: -(size + 3))
        }
        .offset(x: w * CGFloat(slot.slot), y: H * CGFloat(slot.minutes) / 1440 - 1)
        .allowsHitTesting(false)
        .accessibilityLabel(markerLabel(slot))
    }

    private func markerLabel(_ slot: WeekMarkerLayout.Slot) -> String {
        let name: String
        switch slot.kind {
        case .bell: name = "アラーム"
        case .start: name = "開始"
        case .due: name = "締切"
        }
        return slot.extra > 0 ? "\(name) ほか\(slot.extra)件" : name
    }

    private func blockPreview(_ ev: ShiftEvent, w: CGFloat, h: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 3)
        let time = Rules.timeLabel(ev)
        return VStack(alignment: .leading, spacing: 0) {
            Text(ev.title)
                .font(.bar(10 + CGFloat(fontDelta), weight: .bold))
                .lineLimit(1)
                .fixedSize()
            if !time.isEmpty {
                Text(time)
                    .font(.bar(9 + CGFloat(fontDelta), weight: .bold))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .foregroundStyle(EventColor.text(ev.color))
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(minWidth: w, minHeight: h, alignment: .topLeading)
        .background(EventColor.fill(ev.color), in: shape)
        .background(calBg, in: shape)
        .clipShape(shape)
    }

    private func block(_ ev: ShiftEvent, h: CGFloat) -> some View {
        return VStack(alignment: .leading, spacing: 0) {
            Text(ev.title)
                .font(.bar(10 + CGFloat(fontDelta), weight: .bold))
                .lineLimit(2)
            if h > 30 {
                Text(Rules.timeLabel(ev))
                    .font(.bar(9 + CGFloat(fontDelta)))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(EventColor.text(ev.color))
        .padding(2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(EventColor.fill(ev.color), in: RoundedRectangle(cornerRadius: 3))
        .background(calBg, in: RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color(hex: ev.color).opacity(0.55), lineWidth: 1))
    }
}
