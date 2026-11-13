import SwiftUI

/// 予定を保存した。保存先のカレンダーで、その予定の月を開き、その日の予定一覧を開く(RootView が受け取る)。
/// 引数は、日付(日付を決めない予定は nil)と、保存先の共有カレンダーの ID(自分のカレンダーは nil)
private struct EventSavedKey: EnvironmentKey {
    static let defaultValue: (String?, String?) -> Void = { _, _ in }
}

extension EnvironmentValues {
    var eventSaved: (String?, String?) -> Void {
        get { self[EventSavedKey.self] }
        set { self[EventSavedKey.self] = newValue }
    }
}

/// 保存先の候補。calendarId が nil のものが、自分のカレンダー
struct DestinationChoice: Identifiable, Equatable {
    let calendarId: String?
    let name: String
    /// 共有カレンダーのアイコン(自分のカレンダーは空)
    let icon: String
    var enabled = true
    var id: String { calendarId ?? "own" }
}

/// 編集中の予定(自分の形式か、共有の形式)
enum FlowDraft {
    case own(ShiftEvent)
    case shared(SharedEvent)
}

/// 編集画面に渡す、保存先まわりの受け渡し
struct EditorFlow {
    /// いまの保存先(nil は自分のカレンダー)
    var destination: String?
    /// 予定が保存されている場所(新しい予定は、開いた場所)
    var origin: String?
    var choices: [DestinationChoice]
    /// 保存先を切り替える(いまの入力を、一緒に渡す)
    var switchTo: (String?, FlowDraft) -> Void
    /// 保存できた。元の予定が別の場所にあれば消して、保存先のカレンダーで、その月の予定一覧を開く
    var saved: (_ date: String?) -> Void

    /// 保存先が、元と同じか(違うときは、削除は出さない。元の予定は、保存したときに消える)
    var isAtOrigin: Bool { destination == origin }
}

/// 予定の編集。自分のカレンダーと共有カレンダーのどちらにも保存できて、「保存先」を切り替えると、
/// 編集画面の形が切り替わる(共有は、職場・ラベル・休憩のない形)。実際に移るのは、保存したとき
struct EventEditorFlow: View {
    @Environment(Store.self) private var store
    @Environment(SharedViewState.self) private var sharedView
    @Environment(\.eventSaved) private var eventSaved

    /// 画像の追加と取り外し。保存先を切り替えても続けて覚えておく(編集画面ごとに持つと、切り替えた時点で、足した画像が消える)
    @State private var attachments = AttachmentSession()
    /// 保存先を変えたときに作った、画像の写し(写し → 元の画像)。元の保存先に戻したときに、元の画像に戻す
    @State private var copiedFrom: [String: String] = [:]
    /// 保存先を切り替えている途中(画像を写している間)
    @State private var switching = false

    private let isNew: Bool
    /// 保存されている自分の予定(共有の予定を開いたときは nil)
    private let originOwn: ShiftEvent?
    /// 保存されている共有の予定(自分の予定を開いたときは nil)
    private let originShared: SharedEvent?
    /// 開いた場所。nil は自分のカレンダー、それ以外は共有カレンダーの ID
    private let origin: String?

    @State private var destination: String?
    @State private var ownDraft: ShiftEvent
    @State private var sharedDraft: SharedEvent

    private static let placeholder = SharedEvent(id: "", ownerUid: "", sourceKey: SharedEvent.calendarKey, title: "",
                                                 startDate: "", endDate: "", startTime: nil, endTime: nil,
                                                 allDay: true, name: "", color: EventLabel.noneColor)

    init(ownEvent: ShiftEvent, isNew: Bool) {
        self.isNew = isNew
        originOwn = ownEvent
        originShared = nil
        origin = nil
        _destination = State(initialValue: nil)
        _ownDraft = State(initialValue: ownEvent)
        _sharedDraft = State(initialValue: Self.placeholder)
    }

    init(sharedEvent: SharedEvent, calendarId: String, isNew: Bool) {
        self.isNew = isNew
        originOwn = nil
        originShared = sharedEvent
        origin = calendarId
        _destination = State(initialValue: calendarId)
        _ownDraft = State(initialValue: ShiftEvent.newUnplaced())
        _sharedDraft = State(initialValue: sharedEvent)
    }

    var body: some View {
        Group {
            Group {
                if destination != nil {
                    SharedEventEditor(target: SharedEditTarget(event: sharedDraft, isNew: isNew), flow: flow,
                                      session: attachments)
                } else {
                    EventEditor(original: ownDraft, isNew: isNew, flow: flow, session: attachments)
                }
            }
            // 保存先を切り替えると、編集画面を作り直す(入力は、切り替える前に写してある)
            .id(destination ?? "")
        }
        // 保存しないで閉じたら、この編集で足した画像(保存先を変えたときの写しも)を消す
        .onDisappear { attachments.discardIfUncommitted() }
    }

    /// 元の予定に付いていた画像
    private var originImageId: String? { originOwn?.imageId ?? originShared?.imageId }

    // MARK: 保存先

    private var flow: EditorFlow? {
        let list = choices
        // 選べる保存先が 1 つしかなければ、「保存先」の行は出さない
        guard list.filter(\.enabled).count > 1 else { return nil }
        return EditorFlow(destination: destination, origin: origin, choices: list,
                          switchTo: { dest, draft in request(dest, draft) },
                          saved: { date in finish(date) })
    }

    private var choices: [DestinationChoice] {
        // 共有カレンダーの中で作った予定は、だれでも直せる・消せるので、自分のカレンダーへも移せる
        var list = [DestinationChoice(calendarId: nil, name: "自分のカレンダー", icon: "")]
        for c in sharedView.writableCalendars() {
            list.append(DestinationChoice(calendarId: c.id, name: c.name, icon: c.icon))
        }
        return list
    }

    private func request(_ dest: String?, _ draft: FlowDraft) {
        guard dest != destination, !switching else { return }
        // 切り替えるときに、お知らせは出さない(職場・ラベルは、保存したときに共有の形で解除される)
        switching = true
        Task {
            var common = Common(draft)
            common.imageId = await relocatedImage(common.imageId, to: dest)
            apply(dest, common)
            switching = false
        }
    }

    /// 画像を、保存先のカレンダーの置き場へ写す(共有カレンダーの画像は、その参加者だけが読める場所に置くため)。
    /// 元の保存先に戻したときは、元の画像に戻す。写せなかったときは、画像を外す
    private func relocatedImage(_ id: String?, to dest: String?) async -> String? {
        guard let id, AttachmentStore.calendarId(of: id) != dest else { return id }
        let source = copiedFrom[id] ?? id
        if source == originImageId, AttachmentStore.calendarId(of: source) == dest {
            if source != id { attachments.didRemove(id) }
            return source
        }
        guard let copy = await AttachmentCloud.duplicate(id, calendarId: dest) else { return nil }
        // この編集で足した画像や写しは、もう使わないので消す(元の予定の画像は、保存するまで残す)
        if attachments.added.contains(id) { attachments.didRemove(id) }
        attachments.didAdd(copy)
        copiedFrom[copy] = source
        return copy
    }

    private func apply(_ dest: String?, _ common: Common) {
        if let cid = dest {
            // 元の共有カレンダーに戻すときは、元の予定(同じ ID)から、それ以外は新しい予定として作る
            let base = (cid == origin ? originShared : nil) ?? sharedView.newDraft() ?? Self.placeholder
            sharedDraft = common.shared(base: base)
        } else {
            // 自分のカレンダーに戻すときは、元の予定(職場・ラベル・メモなど)に、入力した内容を重ねる
            ownDraft = common.own(base: originOwn ?? .newUnplaced())
        }
        destination = dest
    }

    /// 保存できたあと。保存先が元と違うときは、元の予定を消す(新しい予定には、消すものがない)
    private func finish(_ date: String?) {
        if !isNew, destination != origin {
            if origin == nil, let id = originOwn?.id {
                // 自分の画像は、どの予定からも使われなくなったら、片づけ(sweep)で消える
                store.delete(id: id)
            } else if let e = originShared {
                // 共有カレンダーの画像は、片づけの対象にならないので、ここで消す(移した先には、写しが付いている)
                Task {
                    if await sharedView.delete(id: e.id), let image = e.imageId { await AttachmentCloud.remove(image) }
                }
            }
        }
        eventSaved(date, destination)
    }

    /// 自分の形式と共有の形式の、どちらにもある項目
    private struct Common {
        var title: String
        var placed: Bool
        var startDate: String
        var endDate: String
        var startTime: String?
        var endTime: String?
        var allDay: Bool
        var color: String
        var memo: String
        /// 空は無し
        var url: String
        var imageId: String?

        init(_ draft: FlowDraft) {
            switch draft {
            case .own(let e):
                title = e.title
                placed = e.placed && e.startDate != nil
                startDate = e.startDate ?? ""
                endDate = e.endDate ?? e.startDate ?? ""
                startTime = e.startTime
                endTime = e.endTime
                allDay = e.allDay
                color = e.color
                memo = e.memo
                url = e.url ?? ""
                imageId = e.imageId
            case .shared(let s):
                title = s.title
                placed = s.placed && !s.startDate.isEmpty
                startDate = s.startDate
                endDate = s.endDate
                startTime = s.startTime
                endTime = s.endTime
                allDay = s.allDay
                color = s.color
                memo = s.memo
                url = s.url
                imageId = s.imageId
            }
        }

        func shared(base: SharedEvent) -> SharedEvent {
            var out = SharedEvent(id: base.id, ownerUid: base.ownerUid, sourceKey: base.sourceKey, title: title,
                                  startDate: placed ? startDate : "", endDate: placed ? endDate : "",
                                  startTime: allDay ? nil : startTime, endTime: allDay ? nil : endTime,
                                  allDay: allDay, name: base.name, color: color, barTime: base.barTime)
            out.placed = placed
            out.updatedAt = base.updatedAt
            out.updatedByName = base.updatedByName
            out.memo = memo
            out.url = url
            out.imageId = imageId
            return out
        }

        func own(base: ShiftEvent) -> ShiftEvent {
            var e = base
            e.title = title
            e.placed = placed
            e.startDate = placed ? startDate : nil
            e.endDate = placed ? endDate : nil
            e.allDay = allDay
            e.startTime = allDay ? nil : startTime
            e.endTime = allDay ? nil : endTime
            e.memo = memo
            e.url = url.isEmpty ? nil : url
            e.imageId = imageId
            // 職場・ラベルのない予定は、選んだ色をそのまま使う。ある予定は、色を変えたときだけ個別カラーにする
            if base.workplaceId == nil && base.labelId == nil {
                e.ownColor = color != EventLabel.noneColor
            } else if color != base.color {
                e.ownColor = true
            }
            e.color = color
            return e
        }
    }
}

/// 編集画面の一番上に置く「保存先」の行。押すと、保存先を選ぶシートが開く
struct DestinationSection: View {
    let flow: EditorFlow
    /// 切り替えるときに、いまの入力を渡す
    let draft: () -> FlowDraft
    @State private var picking = false

    private var current: DestinationChoice? { flow.choices.first { $0.calendarId == flow.destination } }

    var body: some View {
        Section {
            Button { picking = true } label: {
                HStack(spacing: 8) {
                    Text("保存先").foregroundStyle(Color.primary)
                    Spacer()
                    if let c = current {
                        DestinationIcon(choice: c, size: 20)
                        Text(c.name).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .sheet(isPresented: $picking) { DestinationSheet(flow: flow, draft: draft) }
        }
    }
}

/// 保存先のアイコン。自分のカレンダーは自分のプロフィールのアイコン、共有カレンダーはそのアイコン
struct DestinationIcon: View {
    let choice: DestinationChoice
    var size: CGFloat = 24

    var body: some View {
        if choice.calendarId == nil {
            MyCalendarIcon(size: size)
        } else {
            CalendarIconView(icon: choice.icon.isEmpty ? CalendarIcon.defaultName : choice.icon, size: size)
        }
    }
}

/// 保存先のカレンダーを選ぶシート
struct DestinationSheet: View {
    let flow: EditorFlow
    let draft: () -> FlowDraft
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(flow.choices) { c in row(c) }
                } header: {
                    Text("この予定を保存するカレンダー")
                } footer: {
                    Text("共有カレンダーに保存した予定は参加者全員が修正・削除できます。")
                }
            }
            .navigationTitle("保存先のカレンダー")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color(.systemGroupedBackground))
    }

    private func row(_ c: DestinationChoice) -> some View {
        let selected = c.calendarId == flow.destination
        let isOrigin = c.calendarId == flow.origin
        return Button {
            if !selected { flow.switchTo(c.calendarId, draft()) }
            dismiss()
        } label: {
            HStack(spacing: 12) {
                DestinationIcon(choice: c)
                VStack(alignment: .leading, spacing: 1) {
                    Text(c.name).foregroundStyle(Color.primary)
                    if c.calendarId != nil { Text("共有").font(.app(11)).foregroundStyle(.secondary) }
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                } else if isOrigin {
                    // 変えたあとで、保存せずに元へ戻す(お知らせは出さない)
                    Text("元に戻す").font(.app(15, weight: .semibold)).foregroundStyle(Color.red)
                }
            }
            .contentShape(Rectangle())
        }
        .disabled(!c.enabled)
        .opacity(c.enabled ? 1 : 0.4)
    }
}
