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
    let onSelectEvent: (ShiftEvent) -> Void

    @AppStorage("unplacedCollapsed") private var collapsed = false
    @State private var confirmRecall = false
    @State private var page = 0
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
                        ForEach(0..<2, id: \.self) { i in
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

            if !collapsed {
                Divider()
                ZStack {
                    TabView(selection: $page) {
                        chipsPage(items, hidden: dragging).tag(0)
                        cardsPage
                            .frame(height: LayoutMath.minUnplacedBody)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .tag(1)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    if dragging { dropPrompt(over: over) }
                }
                .frame(minHeight: LayoutMath.minUnplacedBody,
                       maxHeight: fillHeight ? .infinity : LayoutMath.minUnplacedBody)
                .onDrop(of: [.plainText], delegate: unplaceDelegate)
            }
        }
        .frame(maxHeight: (fillHeight && !collapsed) ? .infinity : nil, alignment: .top)
        .background(Color(.secondarySystemBackground).ignoresSafeArea(edges: .bottom))
        .confirmationDialog("\(anchorMonthText)の配置済み予定をすべて未配置に戻しますか?",
                            isPresented: $confirmRecall, titleVisibility: .visible) {
            Button("未配置に戻す", role: .destructive) {
                withAnimation(.snappy) { _ = store.recallMonth(of: anchor) }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        }
    }

    private func chipsPage(_ items: [ShiftEvent], hidden: Bool) -> some View {
        HStack(spacing: 0) {
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
            VStack(spacing: 8) {
                sideButton("\(anchorMonthShort)を回収") { confirmRecall = true }
                sideButton("並び替え") {
                    withAnimation(.snappy) { store.sortUnplaced() }
                }
                Spacer(minLength: 0)
            }
            .frame(width: 84)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
        }
        .opacity(hidden ? 0 : 1)
        .allowsHitTesting(!hidden)
    }

    private func sideButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.app(12))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(Color.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
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
                 delta: "先月比 " + pd.text, trend: pd.trend, fill: Theme.payFill)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func trendColor(_ t: DeltaFormat.Trend) -> Color {
        switch t {
        case .up: return Theme.monthText
        case .down: return Theme.deltaDown
        case .flat: return Color.secondary
        }
    }

    private func card(title: String, titleColor: Color, period: String, value: String, delta: String,
                      trend: DeltaFormat.Trend, fill: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.app(11)).foregroundStyle(titleColor)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(period).font(.app(10)).foregroundStyle(Color.secondary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(value).font(.app(20, weight: .bold)).foregroundStyle(Color.primary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(delta).font(.app(11)).foregroundStyle(trendColor(trend))
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(fill, in: RoundedRectangle(cornerRadius: 12))
    }

    private func chip(_ ev: ShiftEvent) -> some View {
        let time = Rules.timeLabel(ev)
        return HStack(spacing: 4) {
            Text(ev.title).font(.bar(11, weight: .semibold)).foregroundStyle(EventColor.text(ev.color)).lineLimit(1)
            if !time.isEmpty {
                Text(time).font(.bar(9)).foregroundStyle(EventColor.text(ev.color))
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
        .draggable(ev.id)
    }

    private func chipPreview(_ ev: ShiftEvent) -> some View {
        let time = Rules.timeLabel(ev)
        return HStack(spacing: 4) {
            Text(ev.title).font(.bar(11, weight: .semibold)).foregroundStyle(EventColor.text(ev.color))
            if !time.isEmpty {
                Text(time).font(.bar(9)).foregroundStyle(EventColor.text(ev.color))
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
