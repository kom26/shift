import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("startMonday") private var startMonday = false
    @State private var importing = false
    @State private var message: String?
    @State private var editingWorkplace: Workplace?
    @State private var addingWorkplace = false

    var body: some View {
        NavigationStack {
            Form {
                Section("カレンダー") {
                    Toggle("週の始まりを月曜にする", isOn: $startMonday)
                }
                Section {
                    if store.workplaces.isEmpty {
                        Text("職場が登録されていません")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.workplaces) { w in
                        Button { editingWorkplace = w } label: {
                            HStack(spacing: 10) {
                                Circle().fill(Color(hex: w.color)).frame(width: 12, height: 12)
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
                        EditButton().font(.footnote)
                    }
                }
                Section {
                    Button("クリップボードから読み込む") { importFromClipboard() }
                    Button("JSONファイルを読み込む") { importing = true }
                } header: {
                    Text("Web版のデータ")
                } footer: {
                    Text("Web版の localStorage「shift-sched-events」の中身(JSON)を読み込みます。同じIDの予定は上書きされます。")
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } }
            }
            .sheet(item: $editingWorkplace) { WorkplaceEditor(workplace: $0) }
            .sheet(isPresented: $addingWorkplace) { WorkplaceEditor(workplace: nil) }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { handleFile($0) }
            .alert("読み込み", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") {}
            } message: {
                Text(message ?? "")
            }
        }
    }

    private func importFromClipboard() {
        guard let text = UIPasteboard.general.string else {
            message = "クリップボードに文字列がありません"
            return
        }
        run { try store.importJSON(Data(text.utf8)) }
    }

    private func handleFile(_ result: Result<URL, Error>) {
        run {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            return try store.importJSON(Data(contentsOf: url))
        }
    }

    private func run(_ work: () throws -> Int) {
        do {
            message = "\(try work())件の予定を読み込みました"
        } catch {
            message = "読み込めませんでした: \(error.localizedDescription)"
        }
    }
}
