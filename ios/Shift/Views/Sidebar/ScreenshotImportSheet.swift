import PhotosUI
import SwiftUI

/// スクリーンショットから予定を追加する。
/// 画像(最大 5 枚)を選ぶ → AI が日付と時間を読み取る → 確認して、タイトルと職場・ラベルをまとめて付けて追加する
struct ScreenshotImportSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    var reader: ScreenshotReading = FirebaseScreenshotReader()
    /// 予定を追加したあとに、追加した件数を知らせる(トースト用)
    var onAdded: (Int) -> Void = { _ in }

    private enum Step { case pick, reading, review }
    private static let maxImages = 5

    @State private var step = Step.pick
    @State private var picked: [PhotosPickerItem] = []
    @State private var images: [UIImage] = []
    @State private var lines: [ShiftLine] = []
    /// 追加する日(休みの日は含めない)
    @State private var included: Set<String> = []
    @State private var title = ""
    @State private var workplaceId: String?
    @State private var labelId: String?
    @State private var choosing = false
    @State private var errorMessage: String?

    private var workplace: Workplace? { store.workplaces.first { $0.id == workplaceId } }
    private var addCount: Int { lines.filter { !$0.off && included.contains($0.id) }.count }
    private var canAdd: Bool { addCount > 0 && !title.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .pick: pickView
                case .reading: readingView
                case .review: reviewView
                }
            }
            .navigationTitle(step == .review ? "読み取り結果" : "スクショから予定を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(step == .review ? "やり直す" : "キャンセル") {
                        if step == .review { step = .pick } else { dismiss() }
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Color(.systemGroupedBackground))
        .interactiveDismissDisabled(step == .reading)
    }

    // MARK: 画像を選ぶ

    private var pickView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("シフト表のスクリーンショットから、日付と時間を読み取って、予定をまとめて追加します。タイトルと職場・ラベルは、読み取ったあとに、まとめて付けられます。")
                    .font(.app(14))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("スクリーンショット").font(.app(13, weight: .bold))
                        Spacer()
                        Text("\(images.count) / \(Self.maxImages) 枚").font(.app(12)).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        ForEach(0..<Self.maxImages, id: \.self) { i in slot(i) }
                    }
                    Text("表の続きが何枚かに分かれているときは、まとめて選べます。画面の端が重なって、同じ日が 2 枚に写っても、同じ日は 1 回だけになります。")
                        .font(.app(12))
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lock.fill").foregroundStyle(Theme.payText)
                    Text("選んだ画像は、読み取りのためにだけ、AI(Claude)に送られます。名前や店名など、見せたくない部分は、先に隠してから選んでください。")
                        .font(.app(12))
                        .foregroundStyle(Theme.payText)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.payFill, in: RoundedRectangle(cornerRadius: 14))

                if let errorMessage {
                    Text(errorMessage).font(.app(13)).foregroundStyle(.red)
                }
            }
            .padding(16)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                Task { await read() }
            } label: {
                Text(images.isEmpty ? "画像を選んでください" : "\(images.count)枚を読み取る")
                    .font(.app(16, weight: .bold))
                    .foregroundStyle(Theme.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Theme.accent.opacity(images.isEmpty ? 0.4 : 1), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(images.isEmpty)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(.systemGroupedBackground))
        }
        .onChange(of: picked) { _, items in Task { await loadImages(items) } }
    }

    /// 選んだ画像のサムネイル(×で外せる)。次の空き枠は、画像を選ぶボタン
    @ViewBuilder
    private func slot(_ i: Int) -> some View {
        if i < images.count {
            Image(uiImage: images[i])
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .aspectRatio(3.0 / 5.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .topTrailing) {
                    Button {
                        if i < picked.count { picked.remove(at: i) }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.white, Color.black.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 6, y: -6)
                    .accessibilityLabel("この画像を外す")
                }
        } else if i == images.count {
            PhotosPicker(selection: $picked, maxSelectionCount: Self.maxImages, matching: .images) {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Theme.accent.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .frame(maxWidth: .infinity)
                    .aspectRatio(3.0 / 5.0, contentMode: .fit)
                    .overlay(Image(systemName: "plus").font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.accent))
            }
            .accessibilityLabel("画像を選ぶ")
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.tertiarySystemFill))
                .frame(maxWidth: .infinity)
                .aspectRatio(3.0 / 5.0, contentMode: .fit)
        }
    }

    private func loadImages(_ items: [PhotosPickerItem]) async {
        var loaded: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                loaded.append(image)
            }
        }
        images = loaded
        errorMessage = nil
    }

    // MARK: 読み取り

    private var readingView: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text("読み取っています…").font(.app(15, weight: .semibold))
            Text("画像の枚数によって、数秒〜十数秒かかります。").font(.app(12)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func read() async {
        errorMessage = nil
        step = .reading
        let datas = images.compactMap { ImageShrinker.jpeg(from: $0) }
        guard !datas.isEmpty, datas.count == images.count else {
            errorMessage = "画像を読み込めませんでした"
            step = .pick
            return
        }
        do {
            let result = try await reader.read(images: datas)
            guard !result.isEmpty else {
                errorMessage = "日付と時間を読み取れませんでした。別の画像で試してください"
                step = .pick
                return
            }
            lines = result
            included = Set(result.filter { !$0.off }.map(\.id))
            step = .review
        } catch {
            errorMessage = error.localizedDescription
            step = .pick
        }
    }

    // MARK: 確認と一括設定

    private var reviewView: some View {
        List {
            Section {
                Text("\(rangeText) ・ \(lines.count)日分を読み取りました")
                    .font(.app(13, weight: .semibold))
                    .foregroundStyle(Theme.deltaUp)
            }
            Section {
                HStack {
                    Text("タイトル")
                    TextField("必須", text: $title).multilineTextAlignment(.trailing)
                }
                Button { choosing = true } label: {
                    HStack(spacing: 8) {
                        Text("職場・ラベル").foregroundStyle(Color.primary)
                        Spacer()
                        ColorDot(hex: store.groupColor(workplaceId: workplaceId, labelId: labelId), size: 14)
                        Text(workplace?.name ?? store.label(for: labelId)?.name ?? "指定なし").foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
            } header: {
                Text("まとめて設定")
            } footer: {
                Text("下の予定すべてに付きます。あとから、1 件ずつも直せます。")
            }
            Section {
                ForEach(lines) { line in lineRow(line) }
            } header: {
                Text("追加する予定(タップで、追加する・しないを切り替え)")
            } footer: {
                Text("「休」の日は、追加しません。「24:00」は、翌日の 0 時までの予定として追加します。")
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button { add() } label: {
                Text(addCount == 0 ? "追加する予定がありません" : "\(addCount)件を追加")
                    .font(.app(16, weight: .bold))
                    .foregroundStyle(Theme.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Theme.accent.opacity(canAdd ? 1 : 0.4), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(!canAdd)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(.systemGroupedBackground))
        }
        .sheet(isPresented: $choosing) {
            WorkLabelSheet(workplaceId: workplaceId, labelId: labelId) { newWorkplace, newLabel in
                workplaceId = newWorkplace
                labelId = newWorkplace == nil ? newLabel : nil
                // タイトルが空なら、選んだ職場の名前にする
                if title.trimmingCharacters(in: .whitespaces).isEmpty, let w = workplace { title = w.name }
            }
        }
    }

    private var rangeText: String {
        guard let first = lines.first?.date, let last = lines.last?.date else { return "" }
        func md(_ ds: String) -> String { "\(Rules.ymd(ds).month)/\(Rules.ymd(ds).day)" }
        return "\(md(first))〜\(md(last))"
    }

    private func dateText(_ ds: String) -> String {
        let p = Rules.ymd(ds)
        let wd = Rules.weekdayLabels(startMonday: false)[Rules.weekday(ds)]
        return "\(p.month)/\(p.day)(\(wd))"
    }

    @ViewBuilder
    private func lineRow(_ line: ShiftLine) -> some View {
        let on = included.contains(line.id)
        if line.off {
            HStack(spacing: 10) {
                Image(systemName: "minus.circle").foregroundStyle(.tertiary)
                Text(dateText(line.date)).fontWeight(.semibold).frame(width: 84, alignment: .leading)
                Text("休み(追加しない)")
                Spacer()
            }
            .font(.app(15))
            .foregroundStyle(.secondary)
        } else {
            Button {
                if on { included.remove(line.id) } else { included.insert(line.id) }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: on ? "checkmark.square.fill" : "square")
                        .font(.system(size: 20))
                        .foregroundStyle(on ? Theme.accent : Color.secondary)
                    Text(dateText(line.date)).fontWeight(.semibold).frame(width: 84, alignment: .leading)
                    Text(timeText(line)).strikethrough(!on)
                    Spacer()
                }
                .font(.app(15))
                .foregroundStyle(on ? Color.primary : Color.secondary)
                .contentShape(Rectangle())
            }
        }
    }

    private func timeText(_ line: ShiftLine) -> String {
        guard let s = line.start, let e = line.end else { return "終日" }
        return s + "-" + e
    }

    private func add() {
        let chosen = lines.filter { included.contains($0.id) }
        let events = ShiftLineImport.events(from: chosen, title: title, workplace: workplace,
                                            label: store.label(for: labelId), store: store)
        events.forEach { store.save($0) }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onAdded(events.count)
        dismiss()
    }
}
