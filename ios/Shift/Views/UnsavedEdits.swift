import SwiftUI

/// いま開いている編集画面に、保存していない入力があるか。
/// ウィジェットから開いたときに、入力の途中の画面は残し、何も入力していない画面は閉じて、その日の予定一覧を出すのに使う
@MainActor
final class UnsavedEdits {
    static let shared = UnsavedEdits()

    private var dirty: Set<UUID> = []

    /// どれか 1 つでも、保存していない入力がある
    var any: Bool { !dirty.isEmpty }

    func set(_ id: UUID, dirty isDirty: Bool) {
        if isDirty { dirty.insert(id) } else { dirty.remove(id) }
    }

    func clear(_ id: UUID) { dirty.remove(id) }
}

/// 画面を開いたときの値を覚えておき、そこから変わったら「保存していない入力がある」と知らせる
private struct UnsavedTracker<Value: Equatable>: ViewModifier {
    let value: Value
    @State private var id = UUID()
    @State private var baseline: Value?

    func body(content: Content) -> some View {
        content
            .onAppear {
                if let baseline {
                    // 別の画面から戻ってきたとき(開いたときの値は、そのまま)
                    UnsavedEdits.shared.set(id, dirty: value != baseline)
                } else {
                    baseline = value
                }
            }
            .onChange(of: value) { _, new in
                guard let baseline else { return }
                UnsavedEdits.shared.set(id, dirty: new != baseline)
            }
            .onDisappear { UnsavedEdits.shared.clear(id) }
    }
}

extension View {
    /// 編集画面の入力(保存するときに作る値)を渡す。開いたときから変わっていれば、保存していない入力があるとみなす
    func tracksUnsaved<Value: Equatable>(_ value: Value) -> some View {
        modifier(UnsavedTracker(value: value))
    }
}
