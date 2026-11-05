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
                AccountSection()
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
                    NavigationLink("記念日・誕生日") { AnniversaryListView() }
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
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } }
            }
            .keyboardDismissBar { gapFocused = false }
            .sheet(isPresented: $showBarFont) { BarFontSheet() }
            .sheet(item: $editingWorkplace) { WorkplaceEditor(workplace: $0) }
            .sheet(isPresented: $addingWorkplace) { WorkplaceEditor(workplace: nil) }
        }
    }
}
