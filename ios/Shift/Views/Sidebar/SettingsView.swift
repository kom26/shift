import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("startMonday") private var startMonday = false
    @AppStorage("payBasis") private var payBasis = PayBasis.work.rawValue
    @AppStorage("conflictWarningOn") private var conflictWarningOn = true
    @AppStorage("conflictGapMinutes") private var conflictGapMinutes = 0
    @AppStorage(Appearance.key) private var appearance = Appearance.light
    @FocusState private var gapFocused: Bool
    @State private var showBarFont = false
    @State private var showCalendarBackground = false
    @AppStorage(CalendarBackground.personalKey) private var calendarBackgroundKey = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("表示") {
                    Picker("外観", selection: $appearance) {
                        ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section("カレンダー") {
                    Toggle("週の始まりを月曜にする", isOn: $startMonday)
                    Button { showCalendarBackground = true } label: {
                        HStack {
                            Text("カレンダー背景").foregroundStyle(.primary)
                            Spacer()
                            Text(CalendarBackground.name(calendarBackgroundKey)).font(.app(14)).foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").font(.app(13)).foregroundStyle(.tertiary)
                        }
                    }
                    Button { showBarFont = true } label: {
                        HStack {
                            Text("予定バーの文字サイズ").foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right").font(.app(13)).foregroundStyle(.tertiary)
                        }
                    }
                }
                Section {
                    NavigationLink("記念日・誕生日") { AnniversaryListView() }
                    NavigationLink("ウィジェット") { WidgetSettingsView() }
                }
                Section {
                    Picker("月の見込み給料", selection: $payBasis) {
                        Text("勤務ベース").tag(PayBasis.work.rawValue)
                        Text("給料日ベース").tag(PayBasis.payday.rawValue)
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("見込み給料")
                } footer: {
                    Text(payBasis == PayBasis.payday.rawValue ? "表示中の月に受け取る給料" : "表示中の月に働いた分")
                }
                Section {
                    Toggle("予定が重複している日を赤く注意表示", isOn: $conflictWarningOn)
                    if conflictWarningOn {
                        HStack {
                            Text("予定の間の時間が").lineLimit(1).fixedSize()
                            Spacer(minLength: 0)
                            // 0 のときは空にして、グレーの「0」(プレースホルダー)で入力欄だと分かるようにする
                            TextField("0", text: Binding(
                                get: { conflictGapMinutes == 0 ? "" : String(conflictGapMinutes) },
                                set: { input in
                                    let digits = String(input.filter { $0.isASCII && $0.isNumber }.prefix(6))
                                    conflictGapMinutes = min(max(Int(digits) ?? 0, 0), 1440)
                                }))
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 50)
                                .focused($gapFocused)
                            Text("分未満のとき").lineLimit(1).fixedSize()
                        }
                    }
                } header: {
                    Text("予定の重複(ダブルブッキング)")
                } footer: {
                    Text("※終日予定は重複にカウントされません。\n初期設定(0分):予定が1分でも重なる場合")
                }
                AccountSection()
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } }
            }
            // 開いている設定画面は、後ろの画面とは別に描かれるので、ここでも外観を指定して、切り替えた瞬間に変える
            .preferredColorScheme(appearance.colorScheme)
            .keyboardDismissBar { gapFocused = false }
            .sheet(isPresented: $showBarFont) { BarFontSheet() }
            .sheet(isPresented: $showCalendarBackground) {
                CalendarBackgroundSheet(title: "カレンダー背景", selection: $calendarBackgroundKey)
            }
        }
    }
}
