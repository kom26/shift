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
    @FocusState private var gapFocused: Bool
    @State private var editingWorkplace: Workplace?
    @State private var addingWorkplace = false
    @State private var showBarFont = false

    var body: some View {
        NavigationStack {
            Form {
                Section("カレンダー") {
                    Toggle("週の始まりを月曜にする", isOn: $startMonday)
                    Button { showBarFont = true } label: {
                        HStack {
                            Text("予定バーの文字サイズ").foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right").font(.app(13)).foregroundStyle(.tertiary)
                        }
                    }
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
                    Text("勤務ベース: 表示中の月に働いた分。給料日ベース: 表示中の月に受け取る給料(職場の給料日の設定が必要です)。")
                }
                Section {
                    Toggle("重なりを赤く注意表示", isOn: $conflictWarningOn)
                    if conflictWarningOn {
                        HStack {
                            Text("間の時間が")
                            TextField("0", text: Binding(
                                get: { String(conflictGapMinutes) },
                                set: { input in
                                    let digits = String(input.filter { $0.isASCII && $0.isNumber }.prefix(6))
                                    conflictGapMinutes = min(max(Int(digits) ?? 0, 0), 1440)
                                }))
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 70)
                                .focused($gapFocused)
                            Text("分未満のとき注意")
                        }
                    }
                } header: {
                    Text("シフトの重なり")
                } footer: {
                    if conflictWarningOn {
                        Text("0分: 時間が重なる場合だけ。30分なら、前のシフトの終わりから次の開始まで30分未満でも赤くします")
                    }
                }
                Section {
                    if store.workplaces.isEmpty {
                        Text("職場が登録されていません")
                            .font(.app(13))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.workplaces) { w in
                        Button { editingWorkplace = w } label: {
                            HStack(spacing: 10) {
                                ColorDot(hex: w.color, size: 12)
                                Text(w.name).foregroundStyle(.primary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { store.workplaces[$0].id }
                        ids.forEach { store.deleteWorkplace(id: $0) }
                    }
                    .onMove { store.moveWorkplaces(from: $0, to: $1) }
                    Button("＋ 職場を追加") { addingWorkplace = true }
                } header: {
                    HStack {
                        Text("職場")
                        Spacer()
                        EditButton().font(.app(13))
                    }
                }
                Section {
                    HStack {
                        Text("iCloud で同期")
                        Spacer()
                        Text(CloudSync.iCloudAvailable ? "オン" : "オフ")
                            .foregroundStyle(CloudSync.iCloudAvailable ? Theme.accent : Color.secondary)
                    }
                    if CloudSync.iCloudAvailable, let t = CloudSync.lastSync {
                        HStack {
                            Text("最後の同期")
                            Spacer()
                            Text(t.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("データのバックアップ")
                } footer: {
                    Text(CloudSync.iCloudAvailable
                         ? "予定・職場・よく使う予定は iCloud に自動で保存されます。機種変更しても、同じ Apple ID で iCloud にサインインすれば引き継がれます。"
                         : "iPhone の「設定」で Apple ID にサインインして iCloud をオンにすると、予定が自動で保存され、機種変更でも引き継げます。サインインしなくても今までどおり使えます。")
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完了") { gapFocused = false }
                }
            }
            .sheet(isPresented: $showBarFont) { BarFontSheet() }
            .sheet(item: $editingWorkplace) { WorkplaceEditor(workplace: $0) }
            .sheet(isPresented: $addingWorkplace) { WorkplaceEditor(workplace: nil) }
        }
    }
}
