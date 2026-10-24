import SwiftUI

struct EventMenu: ViewModifier {
    let event: ShiftEvent
    let store: Store
    let previewCornerRadius: CGFloat
    let onEdit: (ShiftEvent) -> Void

    func body(content: Content) -> some View {
        content
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: previewCornerRadius, style: .continuous))
            .contextMenu {
                Button { onEdit(event) } label: { Label("編集", systemImage: "pencil") }
                Button { store.duplicate(id: event.id) } label: { Label("複製", systemImage: "plus.square.on.square") }
                if event.placed {
                    Button { store.unplace(id: event.id) } label: { Label("未配置に戻す", systemImage: "tray.and.arrow.down") }
                }
                Button(role: .destructive) { store.delete(id: event.id) } label: { Label("削除", systemImage: "trash") }
            }
    }
}

extension View {
    func eventMenu(for event: ShiftEvent, store: Store, previewCornerRadius: CGFloat = 4, onEdit: @escaping (ShiftEvent) -> Void) -> some View {
        modifier(EventMenu(event: event, store: store, previewCornerRadius: previewCornerRadius, onEdit: onEdit))
    }
}
