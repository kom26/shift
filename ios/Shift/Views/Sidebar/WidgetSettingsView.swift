import SwiftUI

/// ウィジェットの設定。小(1日)と中(1週間)で、見るカレンダーと表示する項目を別々に決める
struct WidgetSettingsView: View {
    @Environment(Store.self) private var store
    @Environment(CalendarService.self) private var calendarService
    @Environment(SharedViewState.self) private var sharedView
    /// 0: 小 / 1: 中
    @State private var size = 0
    @State private var small = WidgetPrefs.load(WidgetPrefsKey.small)
    @State private var medium = WidgetPrefs.load(WidgetPrefsKey.medium)

    private var prefs: Binding<WidgetPrefs> { size == 0 ? $small : $medium }
    private var activeCalendars: [SharedCalendar] { calendarService.calendars.filter { $0.status == .active } }

    var body: some View {
        Form {
            Section {
                TwoWayPicker("大きさ", selection: $size, first: ("小(1日)", 0), second: ("中(1週間)", 1))
            } footer: {
                Text("ウィジェットは、小と中で別々に設定できます。")
            }
            Section {
                calendarRow(title: "自分のカレンダー", id: nil)
                ForEach(activeCalendars) { cal in calendarRow(title: cal.name, id: cal.id) }
            } header: {
                Text("見るカレンダー")
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
        .onChange(of: small) { _, new in changed(new, key: WidgetPrefsKey.small) }
        .onChange(of: medium) { _, new in changed(new, key: WidgetPrefsKey.medium) }
    }

    private func changed(_ new: WidgetPrefs, key: String) {
        new.save(key)
        WidgetSync.publish(store: store)
        Task { await WidgetSharedFeed.refresh(store: store, calendars: calendarService.calendars, sharedView: sharedView) }
    }

    private func calendarRow(title: String, id: String?) -> some View {
        Button {
            prefs.wrappedValue.calendarId = id
        } label: {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                if prefs.wrappedValue.calendarId == id { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
            }
            .contentShape(Rectangle())
        }
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
            } else {
                toggleRow("労働時間", \.showHours, unavailable: workUnavailableReason != nil)
                toggleRow("見込み給料", \.showEstimatedPay, unavailable: workUnavailableReason != nil)
            }
        } header: {
            Text("表示する項目")
        } footer: {
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
