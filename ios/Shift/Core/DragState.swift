import Foundation
import Observation

/// ドラッグ中かどうかの推定状態。SwiftUI にはドラッグ開始/終了のコールバックが無いため、
/// ドロップ先の delegate (enter/update/exit/perform) から間接的に推定する。
@Observable
final class DragState {
    static let shared = DragState()

    var isDragging = false
    var isOverUnplaced = false
    /// ドラッグ中の予定の id(ドラッグ開始時に設定)
    var draggingId: String?

    @ObservationIgnored private var safetyItem: DispatchWorkItem?
    @ObservationIgnored private var exitItem: DispatchWorkItem?

    /// ドラッグ開始時(draggable のペイロード評価時)に呼ぶ。id をそのまま返す
    func begin(_ id: String) -> String {
        draggingId = id
        return id
    }

    /// ドラッグ中の活動を記録する。8 秒間なにも無ければ自動で解除する。
    func touch() {
        exitItem?.cancel()
        exitItem = nil
        if !isDragging { isDragging = true }
        safetyItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.clear() }
        safetyItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: item)
    }

    /// ドロップ完了。すぐに解除する。
    func ended() {
        clear()
    }

    /// ドロップ先から外れた。0.4 秒以内に touch() が無ければ解除する。
    func exitedTarget() {
        exitItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.clear() }
        exitItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
    }

    private func clear() {
        safetyItem?.cancel()
        safetyItem = nil
        exitItem?.cancel()
        exitItem = nil
        if isDragging { isDragging = false }
        if isOverUnplaced { isOverUnplaced = false }
        if draggingId != nil { draggingId = nil }
    }
}
