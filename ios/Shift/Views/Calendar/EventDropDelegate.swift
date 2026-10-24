import SwiftUI
import UniformTypeIdentifiers

/// 「+」バッジを出さずに move として受けるドロップ処理
struct EventDropDelegate: DropDelegate {
    let resolve: (CGPoint) -> String?
    @Binding var target: String?
    let onDrop: (String, String) -> Void

    init(resolve: @escaping (CGPoint) -> String?, target: Binding<String?>, onDrop: @escaping (String, String) -> Void) {
        self.resolve = resolve
        self._target = target
        self.onDrop = onDrop
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.plainText])
    }

    func dropEntered(info: DropInfo) {
        DragState.shared.touch()
        target = resolve(info.location)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DragState.shared.touch()
        target = resolve(info.location)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        DragState.shared.exitedTarget()
        target = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        DragState.shared.ended()
        let date = resolve(info.location)
        guard let provider = info.itemProviders(for: [.plainText]).first, let date else {
            target = nil
            return false
        }
        _ = provider.loadObject(ofClass: NSString.self) { obj, _ in
            guard let id = obj as? String else { return }
            DispatchQueue.main.async { onDrop(id, date) }
        }
        target = nil
        return true
    }
}
