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
    /// 週表示で、つかんだ側のセグメントが開始日から何日目か(日をまたぐ予定の基準日)
    var grabOffsetDays = 0

    @ObservationIgnored private var safetyItem: DispatchWorkItem?
    @ObservationIgnored private var exitItem: DispatchWorkItem?
    @ObservationIgnored private var beginItem: DispatchWorkItem?

    /// ドラッグ開始時(draggable のペイロード評価時)に呼ぶ。id をそのまま返す
    func begin(_ id: String, grabOffsetDays: Int = 0) -> String {
        draggingId = id
        self.grabOffsetDays = grabOffsetDays
        // ドロップ先に入らずに終わったドラッグでも、元の予定が半透明のまま残らないようにする
        beginItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.clear() }
        beginItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: item)
        return id
    }

    /// ドラッグ中の活動を記録する。8 秒間なにも無ければ自動で解除する。
    func touch() {
        beginItem?.cancel()
        beginItem = nil
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
        beginItem?.cancel()
        beginItem = nil
        if isDragging { isDragging = false }
        if isOverUnplaced { isOverUnplaced = false }
        if draggingId != nil { draggingId = nil }
        grabOffsetDays = 0
    }
}
