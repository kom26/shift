import SwiftUI
import UIKit

/// 予定バーのドラッグ元。動かせるのは、自分の予定と、共有カレンダーの中で作った予定だけ。
/// ほかの人の予定や、共有に出した自分の予定(共有カレンダーを重ねたときや、共有カレンダーの中で見えるもの)は動かせず、
/// 長押しすると、予定の詳細が開く
struct EventDragSource: ViewModifier {
    @Environment(Store.self) private var store
    @Environment(SharedViewState.self) private var shared
    let event: ShiftEvent
    var grabOffsetDays = 0
    /// 予定一覧の行から動かすときは、つかんだ時点から、カレンダーの予定バーと同じ小さな見た目にする
    var barPreview = false
    let onOpen: (ShiftEvent) -> Void
    @AppStorage(BarFontSize.monthKey) private var monthDelta = 0.0
    @AppStorage(BarFontSize.thicknessKey) private var thickness = 0.0

    /// カレンダー上のバーと同じ見た目・長さのプレビュー(1 週に入るぶんの日数 × 1 マスの幅。太さと文字は月表示と同じ)
    private var calendarBarPreview: some View {
        let colW = UIScreen.main.bounds.width / 7
        let days = event.startDate.map { s in max(1, Rules.daysBetween(s, event.endDate ?? s) + 1) } ?? 1
        let font = max(5, FixedWidthTime.fitSize(width: colW - 2 - BarFontSize.sidePadding) + CGFloat(monthDelta))
        let height = max(thickness > 0 ? CGFloat(thickness) : 18, BarFontSize.minBar(font: font))
        return EventBarPreview(event: event, height: height, fontSize: font, minWidth: colW * CGFloat(min(days, 7)) - 2)
    }

    private var allowed: Bool {
        // 開始・締切の印は動かせない(長押しで、編集が開く)
        event.taskMarker == nil && (shared.isOpen ? shared.canDrag(event.id) : !store.isOverlay(event.id))
    }

    @ViewBuilder
    private func dragSource(_ content: Content) -> some View {
        if barPreview {
            content.draggable(DragState.shared.begin(event.id, grabOffsetDays: grabOffsetDays)) {
                calendarBarPreview
            }
        } else {
            content.draggable(DragState.shared.begin(event.id, grabOffsetDays: grabOffsetDays))
        }
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if allowed {
            dragSource(content)
                .opacity((DragState.shared.isDragging && DragState.shared.draggingId == event.id) || DragState.shared.pendingId == event.id ? 0.35 : 1)
        } else {
            content.onLongPressGesture(minimumDuration: 0.4) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onOpen(event)
            }
        }
    }
}

extension View {
    func eventDragSource(_ event: ShiftEvent, grabOffsetDays: Int = 0, barPreview: Bool = false, onOpen: @escaping (ShiftEvent) -> Void) -> some View {
        modifier(EventDragSource(event: event, grabOffsetDays: grabOffsetDays, barPreview: barPreview, onOpen: onOpen))
    }
}
