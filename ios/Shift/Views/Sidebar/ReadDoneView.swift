import SwiftUI

/// 読み取りが終わったことを、チェックマークのアニメーションで知らせる。ボタンを押すと、確認・変更の画面へ進む。
/// 読み取った期間と、勤務・休み・読み取れなかった日の日数を出す(勤務の日数だけだと、少なく見えて不安になるため)
struct ReadDoneView: View {
    let summary: ShiftLineImport.ReadSummary
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
            .frame(width: 96, height: 96)
            Text("読み取りが完了しました")
                .font(.app(18, weight: .bold))
            summaryCard
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

    /// 読み取った期間と内訳
    private var summaryCard: some View {
        VStack(spacing: 12) {
            if let first = summary.first, let last = summary.last {
                VStack(spacing: 2) {
                    Text("読み取った期間").font(.app(12)).foregroundStyle(.secondary)
                    Text(first == last ? Self.dayText(first) : Self.dayText(first) + "〜" + Self.dayText(last))
                        .font(.app(20, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("\(summary.days)日間").font(.app(13)).foregroundStyle(.secondary)
                }
                Divider()
            }
            HStack(spacing: 0) {
                if let tasks = summary.tasks {
                    stat("開始・締切", "\(tasks)", unit: "件", color: Theme.accent)
                } else {
                    stat("勤務", "\(summary.work)", unit: "日", color: Theme.accent)
                    Divider()
                    stat("休み", "\(summary.off)", unit: "日", color: .primary)
                    // 読み取れなかった日は、あるときだけ出す
                    if summary.missing > 0 {
                        Divider()
                        stat("読み取れなかった日", "\(summary.missing)", unit: "日", color: .red)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            if summary.tasks == nil, summary.missing > 0 {
                Text("読み取れなかった日は、次の画面で時間を入力できます")
                    .font(.app(12))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func stat(_ title: String, _ value: String, unit: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.app(12))
                .foregroundStyle(color == .red ? Color.red : Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            (Text(value).font(.app(22, weight: .bold)) + Text(unit).font(.app(13, weight: .semibold)))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }

    /// "11月8日(日)"
    private static func dayText(_ date: String) -> String {
        let p = Rules.ymd(date)
        let wd = Rules.weekdayLabels(startMonday: false)[Rules.weekday(date)]
        return "\(p.month)月\(p.day)日(\(wd))"
    }
}
