import SwiftUI

/// 手動共有の確認。いま共有されている内容と比べて、追加・変更・共有から消える予定をカレンダーで見て、
/// 許可した分だけ共有する。チェックを外した変更は、今回は共有されず、未共有のまま残る
struct ShareReviewSheet: View {
    @Environment(SharedPublisher.self) private var publisher
    @Environment(CalendarService.self) private var service
    @Environment(\.dismiss) private var dismiss
    @AppStorage("startMonday") private var startMonday = false
    let calendar: SharedCalendar
    /// チェックを外した変更(今回は共有しない)
    @State private var excluded: Set<String> = []
    /// 見ている月の 1 日(yyyy-MM-01)
    @State private var month = ""
    @State private var sending = false
    @State private var failed = false

    private var latest: SharedCalendar { service.calendars.first { $0.id == calendar.id } ?? calendar }
    private var changes: [ShareChange] { publisher.pending[calendar.id] ?? [] }
    private var selected: [ShareChange] { changes.filter { !excluded.contains($0.id) } }

    // MARK: 月

    private static func firstOfMonth(_ ds: String) -> String {
        let p = Rules.ymd(ds)
        return String(format: "%04d-%02d-01", p.year, p.month)
    }

    /// その変更がかかる月(日をまたぐ予定は、またいだ月すべて)
    private func months(of change: ShareChange) -> [String] {
        let first = Self.firstOfMonth(change.event.startDate)
        let last = Self.firstOfMonth(change.event.endDate)
        var out = [first]
        var m = first
        while m < last, out.count < 24 {
            m = Rules.addMonths(m, 1)
            out.append(m)
        }
        return out
    }

    private struct MonthCount: Identifiable {
        let month: String
        let count: Int
        var id: String { month }
    }

    /// 変更のある月と、その件数(古い月から)
    private var monthCounts: [MonthCount] {
        var counts: [String: Int] = [:]
        for c in changes { for m in months(of: c) { counts[m, default: 0] += 1 } }
        return counts.keys.sorted().map { MonthCount(month: $0, count: counts[$0] ?? 0) }
    }

    private func count(_ kind: ShareChange.Kind) -> Int { changes.filter { $0.kind == kind }.count }

    private func monthNumber(_ m: String) -> Int { Rules.ymd(m).month }

    private func dayText(_ ds: String) -> String {
        let p = Rules.ymd(ds)
        return "\(p.month)/\(p.day)"
    }

    // MARK: 見た目

    private func tint(_ kind: ShareChange.Kind) -> Color {
        switch kind {
        case .added: return Theme.deltaUp
        case .changed: return Theme.alarm
        case .removed: return Theme.deltaDown
        }
    }

    /// バーに出す文字。時間のある予定は時間、それ以外は予定名
    private func barText(_ c: ShareChange) -> String {
        let e = c.event
        if !e.allDay, let s = e.startTime, let t = e.endTime { return s + "-" + t }
        return e.title
    }

    private func bar(_ c: ShareChange) -> some View {
        let color = tint(c.kind)
        let shape = RoundedRectangle(cornerRadius: 3)
        return Text((c.kind == .added ? "＋ " : "") + barText(c))
            .font(.system(size: 8, weight: .bold))
            .lineLimit(1)
            .strikethrough(c.kind == .removed)
            .foregroundStyle(color)
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, minHeight: 13, alignment: .leading)
            .background(color.opacity(0.14), in: shape)
            .overlay(shape.strokeBorder(color, style: StrokeStyle(lineWidth: 1, dash: c.kind == .changed ? [] : [3, 2])))
            .opacity(excluded.contains(c.id) ? 0.35 : 1)
    }

    private func chip(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.app(12, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.14), in: Capsule())
    }

    // MARK: 本体

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if changes.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle").font(.system(size: 36)).foregroundStyle(Theme.deltaUp)
                        Text("共有していない変更はありません").font(.app(15, weight: .semibold))
                        Text("相手のカレンダーは、あなたの予定と同じ内容です。").font(.app(12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("相手のカレンダーがこう変わります。内容を見て、よければ共有してください。")
                                .font(.app(12))
                                .foregroundStyle(.secondary)
                            summary
                            monthPills
                            monthHeader
                            monthGrid
                            legend
                            list(.added, title: "追加される予定")
                            list(.changed, title: "変わる予定")
                            list(.removed, title: "共有から消える予定")
                        }
                        .padding(16)
                    }
                    bottomBar
                }
            }
            .navigationTitle("共有の確認")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
            }
            .alert("共有できませんでした", isPresented: $failed) {
                Button("OK") {}
            } message: {
                Text("通信を確かめて、もう一度試してください。")
            }
            .onAppear { if month.isEmpty { month = monthCounts.first?.month ?? Self.firstOfMonth(Rules.today()) } }
        }
        .presentationDetents([.large])
        .presentationBackground(Color(.systemBackground))
    }

    private var summary: some View {
        HStack(spacing: 8) {
            if count(.added) > 0 { chip("＋ 追加 \(count(.added))", Theme.deltaUp) }
            if count(.changed) > 0 { chip("変更 \(count(.changed))", Theme.alarm) }
            if count(.removed) > 0 { chip("共有から消える \(count(.removed))", Theme.deltaDown) }
        }
    }

    /// 変更のある月。タップでその月へ
    private var monthPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(monthCounts) { item in
                    let on = item.month == month
                    Button { month = item.month } label: {
                        Text("\(monthNumber(item.month))月 \(item.count)")
                            .font(.app(11, weight: .bold))
                            .foregroundStyle(on ? Theme.onAccent : Color.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(on ? Theme.accent : Color(.tertiarySystemFill), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var monthHeader: some View {
        let p = Rules.ymd(month.isEmpty ? Rules.today() : month)
        return HStack {
            Button { month = Rules.addMonths(month, -1) } label: {
                Image(systemName: "chevron.left").frame(width: 36, height: 32)
            }
            Spacer()
            Text("\(String(p.year))年\(p.month)月").font(.app(15, weight: .bold))
            Spacer()
            Button { month = Rules.addMonths(month, 1) } label: {
                Image(systemName: "chevron.right").frame(width: 36, height: 32)
            }
        }
    }

    private var monthGrid: some View {
        let p = Rules.ymd(month.isEmpty ? Rules.today() : month)
        let weeks = Rules.monthGrid(year: p.year, month: p.month, startMonday: startMonday)
        let labels = Rules.weekdayLabels(startMonday: startMonday)
        return VStack(spacing: 1) {
            HStack(spacing: 1) {
                ForEach(labels, id: \.self) { l in
                    Text(l).font(.app(10)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            ForEach(weeks, id: \.self) { week in weekRow(week) }
        }
        .padding(1)
        .background(Color(.separator).opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private static let barH: CGFloat = 15
    private static let barGap: CGFloat = 2
    private static let maxLanes = 3

    /// 1 週間ぶん。日をまたぐ予定は、本物のカレンダーと同じ 1 本のバーでつなげる。
    /// 色・文字・角は本物のバーのまま、追加・変更・消えるは、枠線の色と点線で区別する
    private func weekRow(_ week: [String]) -> some View {
        let byId = Dictionary(changes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let rows = SpanLayout.rows(events: changes.map { $0.event.shiftEvent() }, weekCells: week.map { Optional($0) })
        let lanes = min(rows.count, Self.maxLanes)
        let hidden = rows.dropFirst(Self.maxLanes).flatMap { $0 }
        let height = max(58, 16 + CGFloat(lanes) * (Self.barH + Self.barGap) + (hidden.isEmpty ? 0 : 12))
        return GeometryReader { geo in
            let colW = geo.size.width / 7
            let font = max(5, FixedWidthTime.fitSize(width: colW - 2 - BarFontSize.sidePadding))
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(week, id: \.self) { ds in
                        let inMonth = Rules.isSameMonth(ds, as: month)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("\(Rules.ymd(ds).day)")
                                .font(.system(size: 9))
                                .foregroundStyle(inMonth ? Color.secondary : Color.secondary.opacity(0.4))
                            Spacer(minLength: 0)
                            let more = hidden.filter { Rules.dateInRange(ds, $0.event.startDate ?? "", $0.event.endDate) }.count
                            if more > 0 {
                                Text("+\(more)").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                            }
                        }
                        .padding(2)
                        .frame(width: colW, height: geo.size.height, alignment: .topLeading)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(Color(.separator).opacity(0.5)).frame(width: 0.5)
                        }
                    }
                }
                ForEach(0..<lanes, id: \.self) { r in
                    ForEach(rows[r]) { s in
                        if let change = byId[s.event.id] {
                            changeBar(s, change: change, font: font)
                                .frame(width: max(0, colW * CGFloat(s.span) - 2), height: Self.barH)
                                .offset(x: colW * CGFloat(s.col) + 1, y: 14 + CGFloat(r) * (Self.barH + Self.barGap))
                        }
                    }
                }
            }
        }
        .frame(height: height)
        .background(Color(.systemBackground))
        .clipped()
    }

    /// 本物のバーに、変更の種類の枠線をかぶせる
    private func changeBar(_ s: BarSpan, change: ShareChange, font: CGFloat) -> some View {
        let color = tint(change.kind)
        let r: CGFloat = 4
        let shape = UnevenRoundedRectangle(topLeadingRadius: s.isStart ? r : 0, bottomLeadingRadius: s.isStart ? r : 0,
                                           bottomTrailingRadius: s.isEnd ? r : 0, topTrailingRadius: s.isEnd ? r : 0)
        return EventBar(span: s, height: Self.barH, fontSize: font)
            .overlay(shape.strokeBorder(color, style: StrokeStyle(lineWidth: 1.2, dash: change.kind == .changed ? [] : [3, 2])))
            .opacity(excluded.contains(change.id) ? 0.35 : (change.kind == .removed ? 0.7 : 1))
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendItem("追加", tint(.added))
            legendItem("変更", tint(.changed))
            legendItem("消える", tint(.removed))
        }
        .font(.app(10))
        .foregroundStyle(.secondary)
    }

    private func legendItem(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).strokeBorder(color, lineWidth: 1.5).frame(width: 12, height: 8)
            Text(text)
        }
    }

    @ViewBuilder
    private func list(_ kind: ShareChange.Kind, title: String) -> some View {
        let items = changes.filter { $0.kind == kind }
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.app(12, weight: .bold)).foregroundStyle(tint(kind)).padding(.top, 4)
                ForEach(items) { c in
                    Button {
                        if excluded.contains(c.id) { excluded.remove(c.id) } else { excluded.insert(c.id) }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: excluded.contains(c.id) ? "square" : "checkmark.square.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(excluded.contains(c.id) ? Color.secondary : Theme.accent)
                            Text(rowTitle(c))
                                .font(.app(14))
                                .strikethrough(kind == .removed)
                                .foregroundStyle(kind == .removed ? Color.secondary : Color.primary)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(dayText(c.event.startDate)).font(.app(12)).foregroundStyle(.secondary)
                        }
                        .frame(minHeight: 40)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func rowTitle(_ c: ShareChange) -> String {
        let e = c.event
        let time = (!e.allDay && e.startTime != nil) ? (e.startTime ?? "") + "-" + (e.endTime ?? "") + " " : ""
        return time + (e.title.isEmpty ? e.name : e.title)
    }

    private var bottomBar: some View {
        VStack(spacing: 6) {
            Button {
                Task {
                    sending = true
                    let ok = await publisher.share(selected, in: latest)
                    sending = false
                    if ok { dismiss() } else { failed = true }
                }
            } label: {
                Text(sending ? "共有しています…" : "この内容で共有する(\(selected.count)件)")
                    .font(.app(16, weight: .bold))
                    .foregroundStyle(Theme.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Theme.accent.opacity(selected.isEmpty || sending ? 0.4 : 1), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(selected.isEmpty || sending)
            Text("チェックを外した変更は、今回は共有されず、未共有のまま残ります")
                .font(.app(11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background(Color(.systemBackground))
        .overlay(alignment: .top) { Divider() }
    }
}
