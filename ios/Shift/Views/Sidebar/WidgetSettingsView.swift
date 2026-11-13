import SwiftUI

/// ウィジェットの設定。小(1日)と中(1週間)で、見るカレンダーと表示する項目を別々に決める。
/// 大きさの切り替えとプレビューは画面の上に固定し、その下の項目(チップ)だけがスクロールする。
/// 項目が多くても、プレビューを見ながらオン・オフできるようにするため
struct WidgetSettingsView: View {
    @Environment(Store.self) private var store
    @Environment(CalendarService.self) private var calendarService
    @Environment(SharedViewState.self) private var sharedView
    @Environment(AuthService.self) private var auth
    @Environment(ProfileSettings.self) private var profile
    @Environment(\.dismiss) private var dismiss
    /// 0: 小 / 1: 中
    @State private var size = 0
    /// プレビュー。false は仮の予定でのイメージ、true はいま設定している内容での本当の表示
    @State private var previewReal = false
    /// プレビューで見ているカレンダーの位置(小・中)。プレビューをタップすると、ウィジェットの切り替えボタンと同じく次へ進む
    @State private var previewIndex = [0, 0]
    /// 画面の中で直している設定。「保存」を押すまで、ウィジェットには渡さない
    @State private var small = WidgetPrefs.load(WidgetPrefsKey.small)
    @State private var medium = WidgetPrefs.load(WidgetPrefsKey.medium)
    private let savedSmall = WidgetPrefs.load(WidgetPrefsKey.small)
    private let savedMedium = WidgetPrefs.load(WidgetPrefsKey.medium)

    private var hasChanges: Bool { small != savedSmall || medium != savedMedium }

    private var prefs: Binding<WidgetPrefs> { size == 0 ? $small : $medium }
    private var activeCalendars: [SharedCalendar] { calendarService.calendars.filter { $0.status == .active } }
    /// プレビューで見ている位置のカレンダーでの設定
    private var viewingPrefs: WidgetPrefs { prefs.wrappedValue.viewing(previewIndex[size]) }
    private var includesOwn: Bool { prefs.wrappedValue.calendarIds.contains("") }
    private var includesShared: Bool { prefs.wrappedValue.calendarIds.contains { !$0.isEmpty } }

    var body: some View {
        VStack(spacing: 0) {
            fixedTop
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    calendarSection
                    if includesOwn { filterSection }
                    itemsSection
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("ウィジェット")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("保存") { save() }.disabled(!hasChanges) }
        }
    }

    private func save() {
        // やめた共有カレンダーは外す(一覧を読み込めているときだけ。読み込み前に消してしまわないように)
        if !calendarService.calendars.isEmpty {
            let alive = Set(activeCalendars.map(\.id))
            small.setCalendars(small.calendarIds.filter { $0.isEmpty || alive.contains($0) })
            medium.setCalendars(medium.calendarIds.filter { $0.isEmpty || alive.contains($0) })
        }
        small.save(WidgetPrefsKey.small)
        medium.save(WidgetPrefsKey.medium)
        WidgetSync.publish(store: store)
        Task { await WidgetSharedFeed.refresh(store: store, calendars: calendarService.calendars, sharedView: sharedView) }
        dismiss()
    }

    // MARK: 上に固定する部分

    private var fixedTop: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                sizeButton("小", sub: "1日", wide: false, value: 0)
                sizeButton("中", sub: "1週間", wide: true, value: 1)
            }
            WidgetPreview(size: size, prefs: viewingPrefs, real: previewReal,
                          workAvailable: workAvailable(viewingPrefs.calendarId),
                          switcher: switcherForPreview)
                .contentShape(Rectangle())
                .onTapGesture { if prefs.wrappedValue.canSwitch { previewIndex[size] += 1 } }
                .frame(height: 166)
            Picker("プレビュー", selection: $previewReal) {
                Text("イメージ").tag(false)
                Text("いまの設定で表示").tag(true)
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    /// プレビューの右上の切り替えボタン(ウィジェットと同じ)
    private var switcherForPreview: WidgetCalendarSwitch? {
        guard prefs.wrappedValue.canSwitch else { return nil }
        guard let id = viewingPrefs.calendarId else { return WidgetCalendarSwitch(icon: nil, me: me) }
        return WidgetCalendarSwitch(icon: activeCalendars.first { $0.id == id }?.icon ?? CalendarIcon.defaultName)
    }

    /// 自分のプロフィール(自分のカレンダーのアイコンに使う)。ログインしていなければ nil
    private var me: DayOwner? {
        guard let account = auth.account else { return nil }
        return DayOwner(uid: account.uid, name: profile.displayName(for: account), avatar: profile.avatar)
    }

    private func sizeButton(_ title: String, sub: String, wide: Bool, value: Int) -> some View {
        let on = size == value
        return Button { size = value } label: {
            HStack(spacing: 7) {
                WidgetSizeGlyph(wide: wide).scaleEffect(0.85)
                Text(title).font(.app(13.5, weight: .bold))
                Text(sub).font(.app(12))
            }
            .foregroundStyle(on ? Theme.accent : Color.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(on ? Theme.accent.opacity(0.12) : Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(on ? Theme.accent : Color.clear, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: チップの欄

    /// 見るカレンダー。複数選べて、選んだ順が、ウィジェット右上のボタンで切り替わる順(チップに番号を出す)
    private var calendarSection: some View {
        let ids = prefs.wrappedValue.calendarIds
        return chipSection("表示するカレンダー",
                           note: ids.count > 1 ? "選んだ順(番号)に、ウィジェット右上のボタンで切り替わります。"
                                               : "2 つ以上選ぶと、ウィジェットの右上に切り替えボタンが出ます。") {
            calendarChip(id: "", name: "自分のカレンダー") {
                // 自分のプロフィールのアイコン(ログインしていなければ、カレンダーの記号)
                MyCalendarIcon(size: 18)
            }
            ForEach(activeCalendars) { cal in
                calendarChip(id: cal.id, name: cal.name) {
                    CalendarIconView(icon: cal.icon.isEmpty ? CalendarIcon.defaultName : cal.icon, size: 18)
                }
            }
        }
    }

    private func calendarChip<Icon: View>(id: String, name: String, @ViewBuilder icon: () -> Icon) -> some View {
        let ids = prefs.wrappedValue.calendarIds
        let order = ids.firstIndex(of: id)
        return WidgetChip(on: order != nil, action: {
            var list = ids
            if let order {
                guard list.count > 1 else { return }  // 最後の 1 つは外せない
                list.remove(at: order)
            } else {
                list.append(id)
            }
            prefs.wrappedValue.setCalendars(list)
            previewIndex[size] = prefs.wrappedValue.wrapped(previewIndex[size])
        }) {
            icon()
            Text(name).lineLimit(1)
            if let order, ids.count > 1 {
                Text("\(order + 1)")
                    .font(.app(10.5, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .frame(minWidth: 17, minHeight: 17)
                    .background(Capsule().fill(Theme.onAccent))
            }
        }
    }

    /// 自分のカレンダーで出す職場・ラベル(自分のカレンダーを選んでいるときだけ)
    private var filterSection: some View {
        chipSection("自分のカレンダーで出す職場・ラベル", note: "何も選ばなければ、すべて出します。") {
            ForEach(store.workplaces) { w in
                colorChip(name: w.name, color: w.color, on: prefs.wrappedValue.workplaceIds.contains(w.id)) { toggle(w.id, \.workplaceIds) }
            }
            ForEach(store.labels) { l in
                colorChip(name: l.name, color: l.color, on: prefs.wrappedValue.labelIds.contains(l.id)) { toggle(l.id, \.labelIds) }
            }
            colorChip(name: "ラベルなし", color: EventLabel.noneColor, on: prefs.wrappedValue.labelIds.contains(Store.noLabelKey)) {
                toggle(Store.noLabelKey, \.labelIds)
            }
        }
    }

    private func colorChip(name: String, color: String, on: Bool, action: @escaping () -> Void) -> some View {
        WidgetChip(on: on, action: action) {
            Circle().fill(Color(hex: color)).frame(width: 9, height: 9)
            Text(name).lineLimit(1)
        }
    }

    private func toggle(_ id: String, _ keyPath: WritableKeyPath<WidgetPrefs, [String]>) {
        var p = prefs.wrappedValue
        if let i = p[keyPath: keyPath].firstIndex(of: id) { p[keyPath: keyPath].remove(at: i) } else { p[keyPath: keyPath].append(id) }
        prefs.wrappedValue = p
    }

    /// 労働時間・見込み給料を出せるか。自分のカレンダーは職場、共有カレンダーは共有している職場が要る
    private func workAvailable(_ calendarId: String?) -> Bool {
        if let id = calendarId {
            let keys = calendarService.calendars.first { $0.id == id }?.mySharedKeys ?? []
            return keys.contains { $0.hasPrefix("w:") }
        }
        return !store.workplaces.isEmpty
    }

    /// 選んだカレンダーのどれでも出せないときの理由(どれかで出せるなら nil)
    private var workUnavailableReason: String? {
        let ids = prefs.wrappedValue.calendarIds
        if ids.contains(where: { workAvailable($0.isEmpty ? nil : $0) }) { return nil }
        return ids == [""] ? "職場が登録されていません" : "勤務予定を共有していません"
    }

    private var itemsSection: some View {
        chipSection("表示する項目", note: itemsNote) {
            itemChip("誕生日", \.showBirthdays)
            itemChip("記念日", \.showAnniversaries)
            itemChip("アラーム", \.showAlarms, scope: "自分のみ", unavailable: !includesOwn)
            itemChip("給料日", \.showPayday, scope: "自分のみ", unavailable: !includesOwn)
            if size == 0 {
                itemChip("共有者のアイコン", \.showOwnerIcons, scope: "共有のみ", unavailable: !includesShared)
            } else {
                itemChip("労働時間", \.showHours, unavailable: workUnavailableReason != nil)
                itemChip("見込み給料", \.showEstimatedPay, unavailable: workUnavailableReason != nil)
            }
        }
    }

    private var itemsNote: String? {
        if size == 0 { return includesShared ? "共有者のアイコンは、共有カレンダーの予定の左に、予定を入れた人のアイコンを出します。" : nil }
        if let reason = workUnavailableReason { return reason + "。労働時間と見込み給料は表示できません。" }
        return "労働時間・見込み給料は、自分のカレンダーと、勤務予定を共有している共有カレンダーで出ます。"
    }

    /// unavailable なら、オフのまま押せない
    private func itemChip(_ title: String, _ keyPath: WritableKeyPath<WidgetPrefs, Bool>, scope: String? = nil,
                          unavailable: Bool = false) -> some View {
        let on = !unavailable && prefs.wrappedValue[keyPath: keyPath]
        return WidgetChip(on: on, disabled: unavailable, action: { prefs.wrappedValue[keyPath: keyPath].toggle() }) {
            Text(title).lineLimit(1)
            if let scope { Text(scope).font(.app(10.5)).opacity(0.75) }
        }
    }

    private func chipSection<Content: View>(_ title: String, note: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.app(12, weight: .medium)).foregroundStyle(.secondary)
            FlowLayout(spacing: 7) { content() }
            if let note {
                Text(note).font(.app(11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// 設定画面のチップ。タップでオン・オフ。オンはアクセント色で塗る
private struct WidgetChip<Label: View>: View {
    let on: Bool
    var disabled = false
    let action: () -> Void
    @ViewBuilder let label: Label

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) { label }
                .font(.app(13))
                .foregroundStyle(on ? Theme.onAccent : Color.primary)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(Capsule().fill(on ? Theme.accent : Color(.secondarySystemGroupedBackground)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
    }
}
