import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct UnplacedArea: View {
    @Environment(Store.self) private var store
    @Environment(Holidays.self) private var holidays
    let anchor: String
    let selectedDate: String?
    let startMonday: Bool
    var fillHeight: Bool = false
    @Binding var stampId: String?
    @Binding var alarmStamp: AlarmPreset?
    let onSelectEvent: (ShiftEvent) -> Void
    var onEditFavorite: (ShiftEvent) -> Void = { _ in }
    var onNewFavorite: () -> Void = {}

    @AppStorage("unplacedCollapsed") private var collapsed = false
    @State private var confirmRecall = false
    @State private var showPayBasis = false
    @State private var favFilter: String?
    /// 0..5。1〜4が実ページ、0と5は端から端へ循環するための複製(止まったら実ページへ瞬間移動)
    @State private var tab = 1
    private static let pageCount = 4
    private var page: Int { (tab - 1 + Self.pageCount) % Self.pageCount }
    @AppStorage("payBasis") private var payBasisRaw = PayBasis.work.rawValue

    private var anchorMonthShort: String {
        "\(Rules.ymd(anchor).month)月"
    }

    private var anchorMonthText: String {
        let p = Rules.ymd(anchor)
        return "\(p.year)年\(p.month)月"
    }

    private var unplaceDelegate: UnplaceDropDelegate {
        UnplaceDropDelegate(onDrop: { id in
            withAnimation(.snappy) { store.unplace(id: id) }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        })
    }

    var body: some View {
        let items = store.unplacedEvents
        let drag = DragState.shared
        let dragging = drag.isDragging
        let over = drag.isOverUnplaced
        VStack(spacing: 0) {
            ZStack {
                if !collapsed {
                    HStack(spacing: 4) {
                        ForEach(0..<Self.pageCount, id: \.self) { i in
                            Circle()
                                .fill(i == page ? Theme.accent : Color.secondary.opacity(0.35))
                                .frame(width: 6, height: 6)
                        }
                    }
                }
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.snappy) { collapsed.toggle() }
                    } label: {
                        Image(systemName: collapsed ? "chevron.up" : "chevron.down")
                            .font(.app(12))
                            .padding(4).contentShape(Rectangle())
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .frame(minHeight: LayoutMath.unplacedHeaderH)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 12).onEnded { v in
                guard !collapsed else { return }
                if v.translation.width < -30 { go(1) } else if v.translation.width > 30 { go(-1) }
            })

            if !collapsed {
                Divider()
                ZStack {
                    TabView(selection: $tab) {
                        pageContent(3, items: items, dragging: dragging).tag(0)
                        pageContent(0, items: items, dragging: dragging).tag(1)
                        pageContent(1, items: items, dragging: dragging).tag(2)
                        pageContent(2, items: items, dragging: dragging).tag(3)
                        pageContent(3, items: items, dragging: dragging).tag(4)
                        pageContent(0, items: items, dragging: dragging).tag(5)
                    }
                    .onChange(of: tab) { _, new in
                        // 該当ページ以外へ移ったらスタンプモードを解除
                        let logical = (new - 1 + Self.pageCount) % Self.pageCount
                        if logical != 0 { stampId = nil }
                        if logical != 3 { alarmStamp = nil }
                        guard new == 0 || new == Self.pageCount + 1 else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            guard tab == new else { return }
                            var t = Transaction()
                            t.disablesAnimations = true
                            withTransaction(t) { tab = new == 0 ? Self.pageCount : 1 }
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    if dragging && !(drag.draggingId?.hasPrefix(Store.favoritePrefix) ?? false) { dropPrompt(over: over) }
                }
                .frame(minHeight: LayoutMath.minUnplacedBody,
                       maxHeight: fillHeight ? .infinity : LayoutMath.minUnplacedBody)
                .onDrop(of: [.plainText], delegate: unplaceDelegate)
            }
        }
        .frame(maxHeight: (fillHeight && !collapsed) ? .infinity : nil, alignment: .top)
        .background(Color(.secondarySystemBackground).ignoresSafeArea(edges: .bottom))
        .sheet(isPresented: $showPayBasis) { PayBasisSheet() }
        .confirmationDialog("\(anchorMonthText)の配置済み予定をすべて未配置に戻しますか?",
                            isPresented: $confirmRecall, titleVisibility: .visible) {
            Button("未配置に戻す", role: .destructive) {
                withAnimation(.snappy) { _ = store.recallMonth(of: anchor) }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        }
    }

    /// ヘッダーのスワイプで隣のページへ(端からは反対側へ循環)
    private func go(_ delta: Int) {
        guard (1...Self.pageCount).contains(tab) else { return }
        withAnimation(.snappy) { tab += delta }
    }

    @ViewBuilder
    private func pageContent(_ logical: Int, items: [ShiftEvent], dragging: Bool) -> some View {
        switch logical {
        case 0: favoritesPage
        case 1: chipsPage(items, hidden: dragging)
        case 2:
            cardsPage.frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
            AlarmPage(stamp: $alarmStamp)
        }
    }

    // MARK: よく使う予定

    private var favoritesPage: some View {
        let list = Rules.sortUnplaced(store.favorites(workplaceFilter: favFilter))
        let suggestions = favFilter == nil ? store.favoriteSuggestions() : []
        return VStack(alignment: .leading, spacing: 4) {
            if !store.workplaces.isEmpty { favoriteFilterRow }
            if stampId != nil { favoriteGuide }
            ScrollView {
                FlowLayout(spacing: 8) {
                    Button(action: onNewFavorite) {
                        Text("＋ 新規")
                            .font(.bar(11, weight: .bold))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .overlay(RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                    }
                    .buttonStyle(.plain)
                    ForEach(list) { favoriteBar($0) }
                    ForEach(suggestions) { suggestionBar($0) }
                }
                .padding(.horizontal, 4)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    private var favoriteFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                filterChip(title: "すべて", color: nil, key: nil)
                ForEach(store.workplaces) { w in filterChip(title: w.name, color: w.color, key: w.id) }
                filterChip(title: "指定なし", color: nil, key: Store.noWorkplaceKey)
            }
            .padding(.horizontal, 3)
            .padding(.vertical, 3)
        }
    }

    private func filterChip(title: String, color: String?, key: String?) -> some View {
        let on = favFilter == key
        return HStack(spacing: 4) {
            if let color { ColorDot(hex: color, size: 8) }
            Text(title).font(.app(11, weight: on ? .semibold : .regular)).lineLimit(1)
        }
        .foregroundStyle(on ? Theme.accent : Color.secondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(on ? Theme.accentSoft : Color(.secondarySystemFill), in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.accent, lineWidth: on ? 1 : 0))
        .contentShape(Capsule())
        .onTapGesture { favFilter = key }
    }

    private func guideTag(_ text: String) -> some View {
        Text(text)
            .font(.app(9.5, weight: .semibold))
            .foregroundStyle(Theme.monthText)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Theme.monthFill, in: RoundedRectangle(cornerRadius: 4))
    }

    private var favoriteGuide: some View {
        HStack(spacing: 12) {
            if stampId == nil {
                HStack(spacing: 4) { guideTag("ドラッグ"); Text("コピーして配置") }
                HStack(spacing: 4) { guideTag("選択"); Text("スタンプモード") }
            } else {
                HStack(spacing: 4) { guideTag("タップ"); Text("配置") }
                HStack(spacing: 4) { guideTag("もう一度タップ"); Text("削除") }
            }
            Spacer(minLength: 0)
        }
        .font(.app(10))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 3)
    }

    private func favoriteBar(_ f: ShiftEvent) -> some View {
        let selected = stampId == f.id
        let time = Rules.timeLabel(f)
        let shape = RoundedRectangle(cornerRadius: 6)
        return HStack(spacing: 5) {
            Text(f.title).font(.bar(11, weight: .bold)).lineLimit(1)
            if !time.isEmpty { Text(time).font(.bar(10, weight: .bold)) }
        }
        .foregroundStyle(EventColor.text(f.color))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(EventColor.fill(f.color))
        .background(Color(.systemBackground))
        .clipShape(shape)
        .overlay { if selected { shape.stroke(Theme.accent, lineWidth: 2).padding(-1) } }
        .overlay(alignment: .topTrailing) {
            if selected {
                Text("選択中")
                    .font(.app(8, weight: .bold))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 5)
                    .background(Theme.accent, in: Capsule())
                    .offset(x: 2, y: -8)
            }
        }
        .opacity(stampId != nil && !selected ? 0.45 : 1)
        .onTapGesture { withAnimation(.snappy) { stampId = selected ? nil : f.id } }
        .contextMenu {
            Button { onEditFavorite(f) } label: { Label("編集", systemImage: "pencil") }
            Button(role: .destructive) {
                if stampId == f.id { stampId = nil }
                store.removeFavorite(id: f.id)
            } label: { Label("削除", systemImage: "trash") }
        }
        .draggable(DragState.shared.begin(Store.favoritePrefix + f.id))
    }

    private func suggestionBar(_ e: ShiftEvent) -> some View {
        let time = Rules.timeLabel(e)
        return HStack(spacing: 6) {
            Button { store.addFavorite(from: e) } label: {
                Text("＋ \(e.title)\(time.isEmpty ? "" : " " + time)")
                    .font(.bar(11))
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            Button { store.hideSuggestion(e) } label: {
                Image(systemName: "xmark").font(.app(9, weight: .bold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("候補を非表示")
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .overlay(RoundedRectangle(cornerRadius: 6)
            .strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])))
    }

    private func chipsPage(_ items: [ShiftEvent], hidden: Bool) -> some View {
        VStack(spacing: 0) {
            toolbar(count: items.count)
            ScrollView {
                if items.isEmpty {
                    Text("すべて配置済みです 🎉")
                        .font(.app(12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(items) { chip($0) }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .contentMargins(.bottom, 8, for: .scrollContent)
        }
        .opacity(hidden ? 0 : 1)
        .allowsHitTesting(!hidden)
    }

    /// 件数と「回収」「並べ替え」(未配置ページの上端。スワイプで一緒に流れる)
    private func toolbar(count: Int) -> some View {
        HStack(spacing: 8) {
            Text("未配置 \(count)件")
                .font(.app(12))
                .foregroundStyle(.secondary)
            sideButton("\(anchorMonthShort)の予定を全て回収") { confirmRecall = true }
            sideButton("並べ替え") {
                withAnimation(.snappy) { store.sortUnplaced() }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: LayoutMath.unplacedToolbarH)
    }

    private func sideButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.app(12))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color(.secondarySystemFill), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func dropPrompt(over: Bool) -> some View {
        ZStack {
            Color(.secondarySystemBackground)
            if over { Theme.accentSoft }
            VStack(spacing: 4) {
                Image(systemName: "tray.and.arrow.down").font(.app(22))
                Text("未配置に戻す").font(.app(15))
            }
            .foregroundStyle(.secondary)
            if over {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    .padding(4)
            }
        }
        .allowsHitTesting(false)
    }

    private var cardsPage: some View {
        let d = store.summaryCards(selectedDate: selectedDate, today: Rules.today(), anchor: anchor,
                                   startMonday: startMonday,
                                   payBasis: PayBasis(rawValue: payBasisRaw) ?? .work,
                                   isHoliday: { holidays.name(on: $0) != nil })
        let wd = DeltaFormat.hours(d.weekHours - d.prevWeekHours)
        let md = DeltaFormat.hours(d.monthHours - d.prevMonthHours)
        let pd = DeltaFormat.yen(d.monthPay - d.prevMonthPay)
        return HStack(spacing: 8) {
            card(title: "週の労働時間", titleColor: Theme.weekText, period: d.weekLabel, value: Rules.formatHours(d.weekHours),
                 delta: "先週比 " + wd.text, trend: wd.trend, fill: Theme.weekFill)
            card(title: "月の労働時間", titleColor: Theme.monthText, period: d.monthLabel, value: Rules.formatHours(d.monthHours),
                 delta: "先月比 " + md.text, trend: md.trend, fill: Theme.monthFill)
            card(title: "見込み給料", titleColor: Theme.payText, period: d.payLabel, value: Money.yen(d.monthPay),
                 delta: "先月比 " + pd.text, trend: pd.trend, fill: Theme.payFill, onGear: { showPayBasis = true })
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func trendColor(_ t: DeltaFormat.Trend) -> Color {
        switch t {
        case .up: return Theme.deltaUp
        case .down: return Theme.deltaDown
        case .flat: return Color.secondary
        }
    }

    private func card(title: String, titleColor: Color, period: String, value: String, delta: String,
                      trend: DeltaFormat.Trend, fill: Color, onGear: (() -> Void)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.app(13, weight: .semibold)).foregroundStyle(titleColor)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(period).font(.app(10)).foregroundStyle(Color.secondary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(value).font(.app(22, weight: .bold)).foregroundStyle(Color.primary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(delta).font(.app(11)).foregroundStyle(trendColor(trend))
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(fill, in: RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .topTrailing) {
            if let onGear {
                Button(action: onGear) {
                    Image(systemName: "gearshape")
                        .font(.app(13))
                        .foregroundStyle(titleColor)
                        .padding(8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("見込み給料の設定")
            }
        }
    }

    private func chip(_ ev: ShiftEvent) -> some View {
        let time = Rules.timeLabel(ev)
        return HStack(spacing: 4) {
            Text(ev.title).font(.bar(11, weight: .semibold)).foregroundStyle(EventColor.text(ev.color)).lineLimit(1)
            if !time.isEmpty {
                Text(time).font(.bar(10, weight: .bold)).foregroundStyle(EventColor.text(ev.color))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(EventColor.fill(ev.color))
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture { onSelectEvent(ev) }
        .eventMenu(for: ev, store: store, onEdit: onSelectEvent) {
            chipPreview(ev)
        }
        .draggable(DragState.shared.begin(ev.id))
        .opacity(DragState.shared.isDragging && DragState.shared.draggingId == ev.id ? 0.35 : 1)
    }

    private func chipPreview(_ ev: ShiftEvent) -> some View {
        let time = Rules.timeLabel(ev)
        return HStack(spacing: 4) {
            Text(ev.title).font(.bar(11, weight: .semibold)).foregroundStyle(EventColor.text(ev.color))
            if !time.isEmpty {
                Text(time).font(.bar(10, weight: .bold)).foregroundStyle(EventColor.text(ev.color))
            }
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(EventColor.fill(ev.color))
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// 未配置エリア全体で受ける move ドロップ
struct UnplaceDropDelegate: DropDelegate {
    let onDrop: (String) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.plainText])
    }

    func dropEntered(info: DropInfo) {
        DragState.shared.touch()
        DragState.shared.isOverUnplaced = true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DragState.shared.touch()
        DragState.shared.isOverUnplaced = true
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        DragState.shared.isOverUnplaced = false
        DragState.shared.exitedTarget()
    }

    func performDrop(info: DropInfo) -> Bool {
        DragState.shared.ended()
        guard let provider = info.itemProviders(for: [.plainText]).first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { obj, _ in
            guard let id = obj as? String else { return }
            DispatchQueue.main.async { onDrop(id) }
        }
        return true
    }
}
