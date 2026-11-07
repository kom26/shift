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
    let onOpen: (ShiftEvent) -> Void

    private var allowed: Bool {
        shared.isOpen ? shared.canDrag(event.id) : !store.isOverlay(event.id)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if allowed {
            content
                .draggable(DragState.shared.begin(event.id, grabOffsetDays: grabOffsetDays))
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
    func eventDragSource(_ event: ShiftEvent, grabOffsetDays: Int = 0, onOpen: @escaping (ShiftEvent) -> Void) -> some View {
        modifier(EventDragSource(event: event, grabOffsetDays: grabOffsetDays, onOpen: onOpen))
    }
}
