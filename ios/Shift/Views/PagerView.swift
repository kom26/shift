import SwiftUI
import UIKit

/// ヘッダーの ‹ › ボタンからページャへスライドを依頼するコマンド
struct PagerCommand: Equatable {
    let direction: Int
    let id: UUID
}

/// 動き出しとみなす最小移動量(pt)。この距離を動くまで、ジェスチャーは始まらない
/// (触れた瞬間から反応させると、iOS 26 で予定バーの長押しドラッグの開始を邪魔する)
private let pagerMoveThreshold: CGFloat = 4

/// 3ページ横並びのページャ。ドラッグ中に高速に変わる状態(dragX など)をすべてここに閉じ込め、
/// 親(RootView)の body を再評価させない。ページは構築済みの値として受け取る。
struct PagerView<Page: View>: View {
    let prev: Page
    let current: Page
    let next: Page
    @Binding var command: PagerCommand?
    let onCommit: (Int) -> Void

    @State private var dragX: CGFloat = 0
    @State private var lockFrames: [CGRect] = []
    @State private var committing = false
    @State private var swipeActive = false
    @GestureState private var touching = false

    init(prev: Page, current: Page, next: Page, command: Binding<PagerCommand?>, onCommit: @escaping (Int) -> Void) {
        self.prev = prev
        self.current = current
        self.next = next
        self._command = command
        self.onCommit = onCommit
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            HStack(spacing: 0) {
                prev.frame(width: w, height: geo.size.height).clipped()
                current.frame(width: w, height: geo.size.height).clipped()
                next.frame(width: w, height: geo.size.height).clipped()
            }
            .frame(width: w * 3, alignment: .leading)
            .offset(x: -w + dragX)
            .clipped()
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: pagerMoveThreshold, coordinateSpace: .named("pager"))
                    .updating($touching) { _, state, _ in state = true }
                    .onChanged { v in
                        let blocked = lockFrames.contains { $0.contains(v.startLocation) }
                        if blocked { return }
                        let dx = v.translation.width
                        let dy = v.translation.height
                        if swipeActive {
                            dragX = dx
                            return
                        }
                        if committing { return }
                        if abs(dx) > abs(dy) {
                            swipeActive = true
                            dragX = dx
                        }
                    }
                    .onEnded { v in
                        guard swipeActive else { return }
                        if committing { swipeActive = false; return }
                        let dx = v.translation.width
                        if abs(dx) > w * 0.25 || abs(v.predictedEndTranslation.width) > w * 0.5 {
                            slide(dx < 0 ? 1 : -1, width: w)
                        } else {
                            withAnimation(.snappy(duration: 0.25)) { dragX = 0 }
                        }
                        swipeActive = false
                    })
            .onChange(of: touching) { _, new in
                if !new && swipeActive && !committing {
                    withAnimation(.snappy) { dragX = 0 }
                    swipeActive = false
                }
            }
            .onChange(of: command) { _, new in
                guard let new else { return }
                if !committing && !swipeActive {
                    slide(new.direction, width: w)
                }
                command = nil
            }
        }
        .coordinateSpace(name: "pager")
        .onPreferenceChange(ScrollLockFramesKey.self) { lockFrames = $0 }
    }

    /// direction: +1 = 次の期間 (左へスライド), -1 = 前の期間
    private func slide(_ direction: Int, width: CGFloat) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        committing = true
        withAnimation(.snappy(duration: 0.25), completionCriteria: .logicallyComplete) {
            dragX = direction > 0 ? -width : width
        } completion: {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                onCommit(direction)
                dragX = 0
                committing = false
            }
        }
    }
}
