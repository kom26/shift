import SwiftUI

/// 予定を選んだ複数の日付へ一括コピーするシート
struct CopyDatesSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let event: ShiftEvent

    @State private var picked: Set<DateComponents> = []

    private var dates: [String] {
        let cal = Calendar.current
        return picked.compactMap { cal.date(from: $0) }.sorted().map { Rules.format($0) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                Text(event.title.isEmpty ? "予定" : event.title)
                    .font(.app(15, weight: .semibold))
                    .padding(.top, 8)
                Text("コピーする日をタップして選びます(複数選択できます)")
                    .font(.app(12))
                    .foregroundStyle(.secondary)
                MultiDatePicker("コピー先", selection: $picked)
                    .padding(.horizontal, 8)
                Spacer(minLength: 0)
            }
            .navigationTitle("日付を選んでコピー")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(dates.isEmpty ? "コピー" : "\(dates.count)日にコピー") {
                        store.copy(id: event.id, to: dates)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        dismiss()
                    }
                    .disabled(dates.isEmpty)
                }
            }
        }
        .presentationDetents([.large])
    }
}
