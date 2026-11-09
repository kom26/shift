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

    private var allowed: Bool {
        shared.isOpen ? shared.canDrag(event.id) : !store.isOverlay(event.id)
    }

    @ViewBuilder
    private func dragSource(_ content: Content) -> some View {
        if barPreview {
            content.draggable(DragState.shared.begin(event.id, grabOffsetDays: grabOffsetDays)) {
                EventBarPreview(event: event, height: 18, fontSize: 11)
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
