import SwiftUI

struct EventMenu<Preview: View>: ViewModifier {
    let event: ShiftEvent
    let store: Store
    let onEdit: (ShiftEvent) -> Void
    let preview: Preview

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button { onEdit(event) } label: { Label("編集", systemImage: "pencil") }
                Button { store.duplicate(id: event.id) } label: { Label("複製", systemImage: "plus.square.on.square") }
                if event.placed {
                    Button { store.unplace(id: event.id) } label: { Label("未配置に戻す", systemImage: "tray.and.arrow.down") }
                }
                Button(role: .destructive) { store.delete(id: event.id) } label: { Label("削除", systemImage: "trash") }
            } preview: {
                preview
            }
    }
}

extension View {
    func eventMenu<Preview: View>(for event: ShiftEvent, store: Store, onEdit: @escaping (ShiftEvent) -> Void,
                                  @ViewBuilder preview: () -> Preview) -> some View {
        modifier(EventMenu(event: event, store: store, onEdit: onEdit, preview: preview()))
    }
}
