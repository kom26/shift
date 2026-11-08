import SwiftUI

/// ウィジェットの設定。小(1日)と中(1週間)で、表示するカレンダーと表示する項目を別々に決める
struct WidgetSettingsView: View {
    @Environment(Store.self) private var store
    @Environment(CalendarService.self) private var calendarService
    @Environment(SharedViewState.self) private var sharedView
    @Environment(\.dismiss) private var dismiss
    /// 0: 小 / 1: 中
    @State private var size = 0
    /// プレビュー。false は仮の予定でのイメージ、true はいま設定している内容での本当の表示
    @State private var previewReal = false
    /// 画面の中で直している設定。「保存」を押すまで、ウィジェットには渡さない
    @State private var small = WidgetPrefs.load(WidgetPrefsKey.small)
    @State private var medium = WidgetPrefs.load(WidgetPrefsKey.medium)
    private let savedSmall = WidgetPrefs.load(WidgetPrefsKey.small)
    private let savedMedium = WidgetPrefs.load(WidgetPrefsKey.medium)

    private var hasChanges: Bool { small != savedSmall || medium != savedMedium }

    private var prefs: Binding<WidgetPrefs> { size == 0 ? $small : $medium }
    private var activeCalendars: [SharedCalendar] { calendarService.calendars.filter { $0.status == .active } }

    var body: some View {
        Form {
            previewSection
            Section {
                calendarPicker
            } header: {
                Text("表示するカレンダー")
            } footer: {
                Text("共有カレンダーの内容は、アプリを開いたときに新しくなります。")
            }
            if prefs.wrappedValue.calendarId == nil {
                filterSection
            }
            itemsSection
        }
        .navigationTitle("ウィジェット")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("保存") { save() }.disabled(!hasChanges) }
        }
    }

    private func save() {
        small.save(WidgetPrefsKey.small)
        medium.save(WidgetPrefsKey.medium)
        WidgetSync.publish(store: store)
        Task { await WidgetSharedFeed.refresh(store: store, calendars: calendarService.calendars, sharedView: sharedView) }
        dismiss()
    }

    /// 大きさの切り替え(記号つき)と、その大きさのプレビュー
    private var previewSection: some View {
        Section {
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    sizeButton("小", sub: "1日", wide: false, value: 0)
                    sizeButton("中", sub: "1週間", wide: true, value: 1)
                }
                WidgetPreview(size: size, prefs: prefs.wrappedValue, real: previewReal,
                              workAvailable: workUnavailableReason == nil)
                Picker("プレビュー", selection: $previewReal) {
                    Text("イメージ").tag(false)
                    Text("いまの設定で表示").tag(true)
                }
                .pickerStyle(.segmented)
                Text(previewReal ? "保存されているデータで表示します。誕生日・記念日・アラームは、登録がないと出ません。"
                     : "仮の予定での見た目です。表示する項目のオン・オフが反映されます。")
                    .font(.app(11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .listRowBackground(Color.clear)
        } footer: {
            Text("ウィジェットは、小と中で別々に設定できます。")
        }
    }

    private func sizeButton(_ title: String, sub: String, wide: Bool, value: Int) -> some View {
        let on = size == value
        return Button { size = value } label: {
            VStack(spacing: 5) {
                WidgetSizeGlyph(wide: wide)
                HStack(spacing: 3) {
                    Text(title).font(.app(13, weight: .bold))
                    Text(sub).font(.app(11))
                }
            }
            .foregroundStyle(on ? Theme.accent : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(on ? Theme.accent.opacity(0.12) : Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(on ? Theme.accent : Color.clear, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 選ぶと一覧が開く(共有カレンダーが増えても、画面が縦に伸びない)
    private var calendarPicker: some View {
        Picker("カレンダー", selection: Binding(get: { prefs.wrappedValue.calendarId ?? "" },
                                               set: { prefs.wrappedValue.calendarId = $0.isEmpty ? nil : $0 })) {
            Text("自分のカレンダー").tag("")
            ForEach(activeCalendars) { cal in Text(cal.name).tag(cal.id) }
        }
        .pickerStyle(.menu)
    }

    @ViewBuilder
    private var filterSection: some View {
        Section {
            ForEach(store.workplaces) { w in
                checkRow(name: w.name, color: w.color, on: prefs.wrappedValue.workplaceIds.contains(w.id)) {
                    toggle(w.id, \.workplaceIds)
                }
            }
            ForEach(store.labels) { l in
                checkRow(name: l.name, color: l.color, on: prefs.wrappedValue.labelIds.contains(l.id)) {
                    toggle(l.id, \.labelIds)
                }
            }
            checkRow(name: "ラベルなし", color: EventLabel.noneColor, on: prefs.wrappedValue.labelIds.contains(Store.noLabelKey)) {
                toggle(Store.noLabelKey, \.labelIds)
            }
        } header: {
            Text("表示する職場・ラベル")
        } footer: {
            Text("何も選ばなければ、すべて表示します。選ぶと、選んだ職場・ラベルの予定だけを表示します。")
        }
    }

    private func checkRow(name: String, color: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Circle().fill(Color(hex: color)).frame(width: 12, height: 12)
                Text(name).foregroundStyle(.primary)
                Spacer()
                if on { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
            }
            .contentShape(Rectangle())
        }
    }

    private func toggle(_ id: String, _ keyPath: WritableKeyPath<WidgetPrefs, [String]>) {
        var p = prefs.wrappedValue
        if let i = p[keyPath: keyPath].firstIndex(of: id) { p[keyPath: keyPath].remove(at: i) } else { p[keyPath: keyPath].append(id) }
        prefs.wrappedValue = p
    }

    /// 労働時間・見込み給料を出せない理由(出せるなら nil)。自分のカレンダーは職場、共有カレンダーは共有している職場が要る
    private var workUnavailableReason: String? {
        if let id = prefs.wrappedValue.calendarId {
            let keys = calendarService.calendars.first { $0.id == id }?.mySharedKeys ?? []
            return keys.contains { $0.hasPrefix("w:") } ? nil : "勤務予定を共有していません"
        }
        return store.workplaces.isEmpty ? "職場が登録されていません" : nil
    }

    @ViewBuilder
    private var itemsSection: some View {
        Section {
            if size == 0 {
                toggleRow("誕生日", \.showBirthdays)
                toggleRow("記念日", \.showAnniversaries)
                if prefs.wrappedValue.calendarId == nil { toggleRow("アラーム", \.showAlarms) }
                toggleRow("給料日", \.showPayday)
                if prefs.wrappedValue.calendarId != nil { toggleRow("共有者・カレンダーのアイコン", \.showOwnerIcons) }
            } else {
                toggleRow("労働時間", \.showHours, unavailable: workUnavailableReason != nil)
                toggleRow("見込み給料", \.showEstimatedPay, unavailable: workUnavailableReason != nil)
            }
        } header: {
            Text("表示する項目")
        } footer: {
            if size == 0, prefs.wrappedValue.calendarId != nil {
                Text("オンにすると、共有カレンダーの予定のバーの左に、予定を入れた人のアイコンを表示します。")
            }
            if size == 1 {
                if let reason = workUnavailableReason {
                    Text(reason + "。労働時間と見込み給料は表示できません。")
                } else if prefs.wrappedValue.calendarId != nil {
                    Text("労働時間と見込み給料は、自分の職場のうち、この共有カレンダーに共有している職場の予定で集計します。")
                } else {
                    Text("中(1週間)は、予定のバーと、週の労働時間・見込み給料を表示します。")
                }
            }
        }
    }

    /// unavailable なら、オフのまま押せない
    private func toggleRow(_ title: String, _ keyPath: WritableKeyPath<WidgetPrefs, Bool>, unavailable: Bool = false) -> some View {
        Toggle(title, isOn: Binding(get: { !unavailable && prefs.wrappedValue[keyPath: keyPath] },
                                    set: { if !unavailable { prefs.wrappedValue[keyPath: keyPath] = $0 } }))
            .disabled(unavailable)
    }
}
