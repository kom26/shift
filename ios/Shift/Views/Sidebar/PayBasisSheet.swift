import SwiftUI

/// 見込み給料の集計の基準(勤務ベース / 給料日ベース)だけを切り替える小さな設定画面
struct PayBasisSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("payBasis") private var payBasis = PayBasis.work.rawValue

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("月の見込み給料", selection: $payBasis) {
                        Text("勤務ベース").tag(PayBasis.work.rawValue)
                        Text("給料日ベース").tag(PayBasis.payday.rawValue)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } footer: {
                    Text("勤務ベース: 表示中の月に働いた分。給料日ベース: 表示中の月に受け取る給料(職場の給料日の設定が必要です)。")
                }
            }
            .navigationTitle("見込み給料の基準")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }
}
