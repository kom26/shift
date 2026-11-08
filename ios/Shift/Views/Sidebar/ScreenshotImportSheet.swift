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

    private enum Step { case pick, reading, done, review }
    private static let maxImages = 5

    @State private var step = Step.pick
    @State private var picked: [PhotosPickerItem] = []
    @State private var images: [UIImage] = []
    @State private var lines: [ShiftLine] = []
    /// 追加する日(休みの日は含めない)
    @State private var included: Set<String> = []
    /// 直した予定(読み取った日の id から引ける)。直した予定には「修正済み」が付き、まとめて設定を変えても、直した内容のまま残る
    @State private var edited: [String: ShiftEvent] = [:]
    @State private var lineEdit: LineEdit?
    @State private var title = ""
    @State private var workplaceId: String?
    @State private var labelId: String?
    @State private var choosing = false
    @State private var errorMessage: String?
    /// 24時をこえる時間の取り込み方(確認のシートで選ぶ)
    @State private var spanChoices = OvernightChoices()
    @State private var showSpanSheet = false
    /// 重複する予定の扱い(読み取った日の id から引ける。選んでいなければ、どちらも残す)
    @State private var dupChoices: [String: DupChoice] = [:]
    @State private var dupTarget: DupTarget?
    /// 年月の指定(写真に年月の表記がないとき)
    @State private var yearMonthOn = false
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var month = Calendar.current.component(.month, from: Date())
    /// 名前の指定(表に複数の名前があるとき)
    @State private var nameOn = false
    @State private var nameText = ""
    @FocusState private var nameFocused: Bool

    private struct DupTarget: Identifiable { let id: String }

    private func choice(_ line: ShiftLine) -> DupChoice { dupChoices[line.id] ?? .both }

    /// この行を取り込むか(チェックが入っていて、「いまの予定を残す」を選んでいない)
    private func isImported(_ line: ShiftLine) -> Bool {
        included.contains(line.id) && !line.off && choice(line) != .keep
    }

    /// この行と重なる、いまの予定(同じ日に、同じ職場。職場がなければ、同じラベル)
    private func duplicates(of line: ShiftLine) -> [ShiftEvent] {
        guard !line.off, let ev = draft(line), let date = ev.startDate else { return [] }
        return store.events.filter { e in
            guard e.placed, e.startDate == date else { return false }
            if let w = ev.workplaceId { return e.workplaceId == w }
            if let l = ev.labelId { return e.workplaceId == nil && e.labelId == l }
            return false
        }
    }

    private var overnightGroups: [OvernightGroup] { ShiftLineImport.overnightGroups(of: lines) }
    private func resolved(_ line: ShiftLine) -> ShiftLine { ShiftLineImport.resolved(line, spanChoices) }
    @FocusState private var titleFocused: Bool

    /// 確認画面から、予定追加と同じ編集画面を開くための組
    private struct LineEdit: Identifiable {
        let id: String
        let event: ShiftEvent
    }

    private var workplace: Workplace? { store.workplaces.first { $0.id == workplaceId } }

    /// その日の予定(直していれば、直した内容。そうでなければ、まとめて設定から作る)
    private func draft(_ line: ShiftLine) -> ShiftEvent? {
        if let e = edited[line.id] { return e }
        return ShiftLineImport.events(from: [resolved(line)], title: title, workplace: workplace,
                                      label: store.label(for: labelId), store: store).first
    }
    private var addCount: Int { lines.filter { isImported($0) }.count }
    private var hasBulkTitle: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    /// タイトルがまだ無い予定か(まとめて設定のタイトルも、1件ずつの入力も無い)
    private func needsTitle(_ line: ShiftLine) -> Bool {
        guard isImported(line) else { return false }
        if let e = edited[line.id] { return e.title.trimmingCharacters(in: .whitespaces).isEmpty }
        return !hasBulkTitle
    }

    private var missingTitleCount: Int { lines.filter(needsTitle).count }
    private var canAdd: Bool { addCount > 0 && missingTitleCount == 0 }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .pick: pickView
                case .reading: readingView
                case .done: doneView
                case .review: reviewView
                }
            }
            .navigationTitle(step == .review ? "読み取り結果" : (step == .done ? "読み取り完了" : "スクショから予定を追加"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(step == .review || step == .done ? "やり直す" : "キャンセル") {
                        if step == .review || step == .done { step = .pick } else { dismiss() }
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Color(.systemGroupedBackground))
        .interactiveDismissDisabled(step == .reading)
        // 文字を打ったあとに、キーボードを閉じるボタンを出す(ほかの画面と同じ)
        .keyboardDismissBar { titleFocused = false; nameFocused = false }
        .sheet(isPresented: $choosing) {
            WorkLabelSheet(workplaceId: workplaceId, labelId: labelId) { newWorkplace, newLabel in
                workplaceId = newWorkplace
                labelId = newWorkplace == nil ? newLabel : nil
                // 職場を選んだら、その名前をタイトルにする(ラベルのときは、読み取り後に、予定を開いて 1 件ずつ入力する)
                title = workplace?.name ?? ""
            }
        }
    }

    /// 読み取り完了。チェックマークを見せてから、ボタンで確認・変更の画面へ
    private var doneView: some View {
        ReadDoneView(workCount: lines.filter { !$0.off }.count) {
            step = .review
            // 24時をこえる時間があれば、取り込む前に、取り込み方を確認する
            showSpanSheet = !overnightGroups.isEmpty
        }
    }

    // MARK: 画像を選ぶ

    private var pickView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("シフト表などのスクリーンショットから\n予定を一括で取り込みます。")
                    .font(.app(14))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 0) {
                    Text("まとめて設定").font(.app(13, weight: .bold)).padding(.bottom, 4)
                    Button { choosing = true } label: {
                        HStack(spacing: 8) {
                            Text("職場・ラベル").foregroundStyle(Color.primary)
                            Spacer()
                            ColorDot(hex: store.groupColor(workplaceId: workplaceId, labelId: labelId), size: 14)
                            Text(workplace?.name ?? store.label(for: labelId)?.name ?? "指定なし").foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        .frame(minHeight: 40)
                        .contentShape(Rectangle())
                    }
                    Text("職場・ラベルを選択すると取り込んだ予定に一括で付与できます。取り込み後に1つずつ選択することも可能です。")
                        .font(.app(12))
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("スクリーンショット").font(.app(13, weight: .bold))
                        Spacer()
                        Text("\(images.count) / \(Self.maxImages) 枚").font(.app(12)).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        ForEach(0..<Self.maxImages, id: \.self) { i in slot(i) }
                    }
                    Text("表が何枚かに分かれる場合でもまとめて取り込みできます。同じ予定が複数枚に写っていても重複せず取り込まれます。")
                        .font(.app(12))
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))

                optionsCard

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lock.fill").foregroundStyle(Theme.payText)
                    Text("選んだ画像は読み取りのためにだけAI(Claude)に送られます。名前や店名など見せたくない部分があれば隠してから選択してください。")
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

    /// 年月と名前の指定(どちらも、必要なときだけ、スイッチをオンにする)
    private var optionsCard: some View {
        VStack(spacing: 14) {
            VStack(spacing: 0) {
                Toggle("写真に年月の表記がない", isOn: $yearMonthOn)
                    .frame(minHeight: 40)
                if yearMonthOn {
                    Divider()
                    HStack {
                        Text("年")
                        Spacer()
                        Picker("年", selection: $year) {
                            ForEach((Calendar.current.component(.year, from: Date()) - 1)...(Calendar.current.component(.year, from: Date()) + 1), id: \.self) {
                                Text("\($0)年").tag($0)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                    .frame(minHeight: 40)
                    Divider()
                    HStack {
                        Text("月")
                        Spacer()
                        Picker("月", selection: $month) {
                            ForEach(1...12, id: \.self) { Text("\($0)月").tag($0) }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                    .frame(minHeight: 40)
                    Text("選んだ年月に合わせて、日付を読み取ります。")
                        .font(.app(12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, yearMonthOn ? 6 : 0)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))

            VStack(spacing: 0) {
                Toggle("シフト表に複数の名前がある", isOn: $nameOn)
                    .frame(minHeight: 40)
                if nameOn {
                    Divider()
                    HStack {
                        Text("読み取る名前")
                        TextField("名前を入力", text: $nameText)
                            .multilineTextAlignment(.trailing)
                            .focused($nameFocused)
                    }
                    .frame(minHeight: 40)
                    Text("この名前のシフトだけを読み取ります。")
                        .font(.app(12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, nameOn ? 6 : 0)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        }
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
            let name = nameOn ? nameText.trimmingCharacters(in: .whitespacesAndNewlines) : ""
            let options = ScreenshotReadOptions(name: name.isEmpty ? nil : name,
                                                yearMonth: yearMonthOn ? String(format: "%04d-%02d", year, month) : nil)
            var result = try await reader.read(images: datas, options: options)
            // 年月の表記がない写真は、選んだ年月に合わせる
            if yearMonthOn { result = ShiftLineImport.alignYearMonth(result, year: year, month: month) }
            guard !result.isEmpty else {
                errorMessage = "日付と時間を読み取れませんでした。別の画像で試してください"
                step = .pick
                return
            }
            lines = result
            included = Set(result.filter { !$0.off }.map(\.id))
            edited = [:]
            dupChoices = [:]
            spanChoices = OvernightChoices()
            // すぐには進まず、読み取りが終わったことを見せてから、ボタンで確認・変更の画面へ
            step = .done
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            errorMessage = error.localizedDescription
            step = .pick
        }
    }

    // MARK: 確認と一括設定

    private var reviewView: some View {
        List {
            // 枠(白い背景)なしで、文字だけ出す
            Section {
                Text("\(rangeText)の\(Set(lines.map(\.date)).count)日分を読み取りました。")
                    .font(.app(13, weight: .semibold))
                    .foregroundStyle(Theme.deltaUp)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 0, trailing: 0))
            }
            if !overnightGroups.isEmpty {
                Section {
                    Button { showSpanSheet = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "moon.stars.fill").foregroundStyle(.orange)
                            Text(overnightBannerText)
                                .font(.app(14, weight: .semibold))
                                .foregroundStyle(Color.primary)
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                }
                .listRowBackground(Color.orange.opacity(0.14))
            }
            Section {
                ForEach(lines) { line in lineRow(line) }
            } header: {
                Text("予定をタップすると1 件ずつ修正できます。\nチェックを外した予定は取り込まれません。")
                    .textCase(nil)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button { add() } label: {
                Text(addCount == 0 ? "追加する予定がありません"
                     : (missingTitleCount > 0 ? "タイトル未入力が\(missingTitleCount)件あります" : "\(addCount)件を追加"))
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
        .sheet(isPresented: $showSpanSheet) {
            DaySpanSheet(groups: overnightGroups, choices: $spanChoices) { line in
                var e = ShiftLineImport.events(from: [line], title: title.isEmpty ? "予定" : title, workplace: workplace,
                                               label: store.label(for: labelId), store: store).first
                // 職場・ラベルを選んでいなければ、見やすい赤系の時間表示にする(選んでいれば、その職場・ラベルの表示ルール)
                if workplace == nil, store.label(for: labelId) == nil {
                    e?.color = "#f28d8d"
                    e?.barShowsTitle = nil
                }
                return e
            }
        }
        .sheet(item: $dupTarget) { target in
            if let line = lines.first(where: { $0.id == target.id }), let incoming = draft(line) {
                DupChoiceSheet(dateText: dateText(resolved(line).date), byLabel: incoming.workplaceId == nil,
                               existing: duplicates(of: line), incoming: incoming,
                               choice: Binding(get: { choice(line) }, set: { dupChoices[line.id] = $0 }))
            }
        }
        .sheet(item: $lineEdit) { target in
            EventEditor(original: target.event, isNew: false, onCommit: { edited[target.id] = $0 })
        }
    }

    /// 確認が要る予定の案内(日をまたぐ予定、24時以降に開始する予定、その両方)
    private var overnightBannerText: String {
        let kinds = Set(overnightGroups.map(\.kind))
        if kinds.count == 2 { return "日をまたぐ予定・24時以降の予定があります。" }
        return kinds.contains(.afterMidnight) ? "24時以降に開始する予定があります。" : "日をまたぐ予定があります。"
    }

    private var rangeText: String {
        guard let first = lines.first?.date, let last = lines.last?.date else { return "" }
        func md(_ ds: String) -> String { "\(Rules.ymd(ds).month)月\(Rules.ymd(ds).day)日" }
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
            VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                // 左のチェックで、追加する・しないを切り替える
                Button {
                    if on { included.remove(line.id) } else { included.insert(line.id) }
                } label: {
                    Image(systemName: on ? "checkmark.square.fill" : "square")
                        .font(.system(size: 20))
                        .foregroundStyle(on ? Theme.accent : Color.secondary)
                        .frame(width: 36, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(on ? "追加しない" : "追加する")
                // 予定をタップすると、予定追加と同じ画面で直せる
                Button {
                    if let e = draft(line) { lineEdit = LineEdit(id: line.id, event: e) }
                } label: {
                    HStack(spacing: 8) {
                        Text(dateText(resolved(line).date)).fontWeight(.semibold).frame(width: 84, alignment: .leading)
                        Text(timeText(line)).strikethrough(!on || choice(line) == .keep)
                        if let n = line.name {
                            Text(n).font(.app(11)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        if needsTitle(line) {
                            Text("タイトル未入力")
                                .font(.app(11, weight: .bold))
                                .foregroundStyle(.red)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.red.opacity(0.12), in: Capsule())
                        }
                        if edited[line.id] != nil {
                            Text("修正済み")
                                .font(.app(11, weight: .bold))
                                .foregroundStyle(Theme.accent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Theme.accent.opacity(0.14), in: Capsule())
                        }
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .font(.app(15))
                    .foregroundStyle(on ? Color.primary : Color.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
            }
            dupChip(line)
            }
        }
    }

    /// 重複する予定がある行の、扱いの表示。押すと、その日だけの選択が開く
    @ViewBuilder
    private func dupChip(_ line: ShiftLine) -> some View {
        if included.contains(line.id), !duplicates(of: line).isEmpty {
            let c = choice(line)
            Button { dupTarget = DupTarget(id: line.id) } label: {
                // まだ選んでいないときは案内、選んだあとは、選んだ内容
                Text(dupChoices[line.id] == nil ? "既に同日に予定があります"
                     : "同日予定・" + (c == .keep ? "取り込まない" : c == .replace ? "置き換え" : "どちらも残す"))
                    .font(.app(11, weight: .bold))
                    .foregroundStyle(Color.orange)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.15), in: Capsule())
            }
            .buttonStyle(.borderless)
            .padding(.leading, 44)
        }
    }

    /// 一覧に出す時間(直した予定は、直した時間)
    private func timeText(_ line: ShiftLine) -> String {
        if let e = edited[line.id] {
            guard !e.allDay, let s = e.startTime, let t = e.endTime else { return "終日" }
            return s + "-" + t
        }
        let r = resolved(line)
        guard let s = r.start, let e = r.end else { return "終日" }
        return s + "-" + e
    }

    private func add() {
        let chosen = lines.filter { isImported($0) }
        // 「置き換える」を選んだ日は、先に、いまの予定を消す
        for line in chosen where choice(line) == .replace {
            duplicates(of: line).forEach { store.delete(id: $0.id) }
        }
        // 直した予定は、直した内容のまま。それ以外は、まとめて設定から作る
        let events = chosen.flatMap { line -> [ShiftEvent] in
            if let e = edited[line.id] { return [e] }
            return ShiftLineImport.events(from: [resolved(line)], title: title, workplace: workplace,
                                          label: store.label(for: labelId), store: store)
        }
        events.forEach { store.save($0) }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onAdded(events.count)
        dismiss()
    }
}
