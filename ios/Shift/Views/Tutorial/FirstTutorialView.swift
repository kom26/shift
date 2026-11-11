import AVFoundation
import SwiftUI
import UIKit

/// 初めての紹介(動画つきの 4 つ)。「使い始める」を押すまで、アプリを開くたびに出す。押したら、見たことにして、もう出さない
enum FirstTutorial {
    /// 見たかどうか(アカウントにも預ける)
    static let doneKey = "tutorialDone"

    struct Item: Identifiable {
        let id: Int
        let title: String
        let text: String
        /// Resources の動画(tutorial<id>.mp4)と、止まった 1 コマ(tutorial<id>.jpg)
        var video: String { "tutorial\(id)" }
    }

    static let items: [Item] = [
        Item(id: 1, title: "よく使う予定",
             text: "よく使う予定を選んで、カレンダーの日付をタップするだけ。同じシフトをまとめて入れられます。"),
        Item(id: 2, title: "予定の移動",
             text: "予定を長押ししてドラッグすると、ほかの日に動かせます。未配置に入れて、あとからカレンダーに戻すこともできます。"),
        Item(id: 3, title: "AI自動取り込み",
             text: "シフト表のスクリーンショットを選ぶと、AIが日付と時間を読み取ってカレンダーに入れます。"),
        Item(id: 4, title: "共有カレンダー",
             text: "招待のQRで友だちや家族が参加して、お互いのシフトを1つのカレンダーに重ねて見られます。"),
    ]

    /// 出すか。「使い始める」を押していない人に、アプリを開くたびに出す(予定などが入っていても出す)。
    /// 招待のリンクで開いた人や、参加の手続きが残っている人には、そのあいだは出さない(済んだあとの、ふつうの起動で出す)
    static func shouldShow(defaults: UserDefaults = .standard, hasInvite: Bool) -> Bool {
        !defaults.bool(forKey: doneKey) && !hasInvite
    }
}

struct FirstTutorialView: View {
    /// 最後の「使い始める」を押した(見たことにする)
    let onStart: () -> Void
    /// 「あとで見る」を押した(見たことにしない。次に開いたときに、また出す)
    let onLater: () -> Void

    @State private var inPages = false
    @State private var page = 0
    private let items = FirstTutorial.items
    private var last: Int { items.count - 1 }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            if inPages {
                pagesView.transition(.move(edge: .trailing))
            } else {
                introView.transition(.move(edge: .leading))
            }
        }
        .animation(.snappy, value: inPages)
    }

    // MARK: 最初の画面

    private var introView: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("シフトパレットへようこそ").font(.app(26, weight: .bold))
                Text("はじめに、便利な使い方を\(items.count)つ紹介します。")
                    .font(.app(14))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            .padding(.top, 24)
            VStack(spacing: 10) {
                ForEach(items) { item in
                    HStack(spacing: 14) {
                        TutorialPoster(item: item)
                            .frame(width: 52, height: 112)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title).font(.app(16, weight: .bold))
                            Text(item.text).font(.app(13)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 8)
                    .padding(.leading, 8)
                    .padding(.trailing, 14)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                }
            }
            Spacer(minLength: 0)
            VStack(spacing: 8) {
                Button {
                    page = 0
                    inPages = true
                } label: {
                    Text("\(items.count)つ見る")
                        .font(.app(17, weight: .bold))
                        .foregroundStyle(Theme.onAccent)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Theme.accent, in: Capsule())
                }
                Button(action: onLater) {
                    Text("あとで見る")
                        .font(.app(16, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .contentShape(Rectangle())
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: 動画のページ(スワイプでも、「次へ」でも行き来できる)

    private var pagesView: some View {
        VStack(spacing: 16) {
            HStack {
                Color.clear.frame(width: 72, height: 44)
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    ForEach(items.indices, id: \.self) { i in
                        Capsule()
                            .fill(i == page ? Theme.accent : Color(.systemGray4))
                            .frame(width: i == page ? 24 : 8, height: 8)
                    }
                }
                .animation(.snappy, value: page)
                Spacer(minLength: 0)
                // 「スキップ」は、「使い始める」のあるページまで進める(最後のページでは出さない)
                Button { withAnimation(.snappy) { page = last } } label: {
                    Text("スキップ").font(.app(14, weight: .bold)).foregroundStyle(Theme.accent)
                        .frame(width: 72, height: 44, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(page == last ? 0 : 1)
                .disabled(page == last)
            }
            TabView(selection: $page) {
                ForEach(items.indices, id: \.self) { i in
                    pageContent(items[i], active: page == i).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            Button {
                if page == last {
                    onStart()
                } else {
                    withAnimation(.snappy) { page += 1 }
                }
            } label: {
                Text(page == last ? "使い始める" : "次へ")
                    .font(.app(17, weight: .bold))
                    .foregroundStyle(Theme.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Theme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func pageContent(_ item: FirstTutorial.Item, active: Bool) -> some View {
        VStack(spacing: 16) {
            TutorialVideo(item: item, active: active)
                .aspectRatio(390.0 / 844.0, contentMode: .fit)
                .frame(maxWidth: 204)
                .frame(maxHeight: .infinity)
            VStack(spacing: 8) {
                Text(item.title).font(.app(22, weight: .bold))
                Text(item.text)
                    .font(.app(14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 96, alignment: .top)
        }
    }
}

// MARK: 止まった 1 コマ

private func tutorialImage(_ item: FirstTutorial.Item) -> UIImage? {
    Bundle.main.path(forResource: item.video, ofType: "jpg").flatMap { UIImage(contentsOfFile: $0) }
}

/// 最初の画面の、動画の 1 コマ
struct TutorialPoster: View {
    let item: FirstTutorial.Item

    var body: some View {
        Group {
            if let image = tutorialImage(item) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color(.tertiarySystemFill)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(.separator), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}

// MARK: 音なし・ボタンなしで、ずっと繰り返す動画

struct TutorialVideo: View {
    let item: FirstTutorial.Item
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            TutorialPoster(item: item)
            // 動きを減らす設定のときは、止まった 1 コマだけ
            if !reduceMotion, let url = Bundle.main.url(forResource: item.video, withExtension: "mp4") {
                LoopingPlayer(url: url, active: active)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .accessibilityLabel(item.title + "の動画")
    }
}

private struct LoopingPlayer: UIViewRepresentable {
    let url: URL
    let active: Bool

    final class Coordinator {
        var player: AVQueuePlayer?
        var looper: AVPlayerLooper?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        let player = AVQueuePlayer()
        player.isMuted = true
        context.coordinator.looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        context.coordinator.player = player
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
        guard let player = context.coordinator.player else { return }
        if active {
            player.play()
        } else {
            // 見えなくなったら止めて、戻ってきたときは、はじめから流す
            player.pause()
            player.seek(to: .zero)
        }
    }

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
