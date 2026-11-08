import SwiftUI

/// 読み取りが終わったことを、チェックマークのアニメーションで知らせる。ボタンを押すと、確認・変更の画面へ進む
struct ReadDoneView: View {
    let workCount: Int
    let offCount: Int
    let onNext: () -> Void

    @State private var ring: CGFloat = 0
    @State private var popped = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack {
                Circle().stroke(Theme.accent.opacity(0.15), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: ring)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "checkmark")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .scaleEffect(popped ? 1 : 0.2)
                    .opacity(popped ? 1 : 0)
            }
            .frame(width: 110, height: 110)
            Text("\(workCount)件の読み込みが完了しました")
                .font(.app(18, weight: .bold))
            if offCount > 0 {
                Text("休みの\(offCount)日は、追加しません。")
                    .font(.app(13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onNext) {
                Text("確認・変更する")
                    .font(.app(16, weight: .bold))
                    .foregroundStyle(Theme.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.easeOut(duration: 0.55)) { ring = 1 }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.55).delay(0.45)) { popped = true }
        }
        .accessibilityElement(children: .combine)
    }
}
