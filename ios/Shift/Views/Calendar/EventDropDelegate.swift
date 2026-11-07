import SwiftUI
import UniformTypeIdentifiers

/// 「+」バッジを出さずに move として受けるドロップ処理
struct EventDropDelegate: DropDelegate {
    let resolve: (CGPoint) -> String?
    @Binding var target: String?
    let onDrop: (String, String) -> Void
    /// ドロップ先の名前(離した場所を、画面全体の座標にするのに使う)
    let originKey: String?
    /// 離した場所のセルの枠(ドロップ先の部品の中の座標)。なければ、離した場所の 1 点
    let cellRect: ((CGPoint) -> CGRect)?

    init(resolve: @escaping (CGPoint) -> String?, target: Binding<String?>, originKey: String? = nil,
         cellRect: ((CGPoint) -> CGRect)? = nil, onDrop: @escaping (String, String) -> Void) {
        self.resolve = resolve
        self._target = target
        self.originKey = originKey
        self.cellRect = cellRect
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
        // ended() は draggingId を消すので、先に置き先を解決する
        let date = resolve(info.location)
        let origin = originKey.flatMap { DragState.shared.dropOrigins[$0] } ?? .zero
        DragState.shared.dropPoint = CGPoint(x: origin.x + info.location.x, y: origin.y + info.location.y)
        let local = cellRect?(info.location) ?? CGRect(origin: info.location, size: .zero)
        DragState.shared.dropRect = local.offsetBy(dx: origin.x, dy: origin.y)
        DragState.shared.ended()
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
