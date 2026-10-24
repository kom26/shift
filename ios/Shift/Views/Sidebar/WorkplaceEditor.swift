import SwiftUI

struct WorkplaceEditor: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// nil なら新規
    let workplace: Workplace?

    @State private var name: String
    @State private var color: String
    @State private var confirmApply = false

    init(workplace: Workplace?) {
        self.workplace = workplace
        _name = State(initialValue: workplace?.name ?? "")
        _color = State(initialValue: workplace?.color ?? Store.defaultColors[0])
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var affectedCount: Int {
        guard let workplace else { return 0 }
        return store.eventCount(matchingTitle: workplace.name)
    }
    private var changed: Bool {
        guard let workplace else { return false }
        return trimmed != workplace.name || color != workplace.color
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("職場の名前", text: $name)
                }
                Section("色") {
                    HStack(spacing: 10) {
                        ForEach(Store.defaultColors, id: \.self) { c in
                            Circle()
                                .fill(Color(hex: c))
                                .frame(width: 24, height: 24)
                                .overlay(Circle().stroke(Color.primary, lineWidth: color == c ? 2 : 0).padding(-3))
                                .onTapGesture { color = c }
                        }
                    }
                    ColorPicker("カスタム色",
                                selection: Binding(get: { Color(hex: color) }, set: { color = $0.toHex() }),
                                supportsOpacity: false)
                }
            }
            .navigationTitle(workplace == nil ? "職場を追加" : "職場を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.disabled(trimmed.isEmpty)
                }
            }
            .confirmationDialog(
                "タイトルが『\(workplace?.name ?? "")』の予定 \(affectedCount) 件にも変更を反映しますか?",
                isPresented: $confirmApply, titleVisibility: .visible
            ) {
                Button("反映する") { commit(applyToEvents: true) }
                Button("この職場だけ変更") { commit(applyToEvents: false) }
                Button("キャンセル", role: .cancel) {}
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        if workplace != nil, changed, affectedCount >= 1 {
            confirmApply = true
        } else {
            commit(applyToEvents: false)
        }
    }

    private func commit(applyToEvents: Bool) {
        if let workplace {
            store.updateWorkplace(id: workplace.id, name: trimmed, color: color, applyToEvents: applyToEvents)
        } else {
            store.addWorkplace(name: trimmed, color: color)
        }
        dismiss()
    }
}
