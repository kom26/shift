import SwiftUI
import UIKit

struct BulkImportSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var color = Store.defaultColors[0]

    private static let example = "早番シフト⇥7:00から15:00まで\n夜勤バイト⇥22:00から翌朝\n遅番シフト⇥"

    private var rows: [(title: String, memo: String)] { BulkImport.parse(text) }

    var body: some View {
        let rows = self.rows
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("エクセル・スプシから予定名・メモをコピーして貼り付け（タブ区切り2列、1行1予定）")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $text)
                            .scrollContentBackground(.hidden)
                            .padding(4)
                            .frame(minHeight: 140)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                        if text.isEmpty {
                            Text(Self.example)
                                .font(.callout)
                                .foregroundStyle(.secondary.opacity(0.5))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 12)
                                .allowsHitTesting(false)
                        }
                    }

                    Button {
                        if let s = UIPasteboard.general.string { text = s }
                    } label: {
                        Label("クリップボードから貼り付け", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.bordered)

                    if !rows.isEmpty {
                        preview(rows)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("色").font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            ForEach(Store.defaultColors, id: \.self) { c in
                                Circle()
                                    .fill(Color(hex: c))
                                    .frame(width: 26, height: 26)
                                    .overlay(Circle().stroke(Color.primary, lineWidth: color == c ? 2 : 0).padding(-3))
                                    .onTapGesture { color = c }
                            }
                        }
                    }

                    Button {
                        store.append(BulkImport.makeEvents(rows, color: color))
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        dismiss()
                    } label: {
                        Text("\(rows.count)件取り込む")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(rows.isEmpty)
                }
                .padding(16)
            }
            .navigationTitle("一括取り込み")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func preview(_ rows: [(title: String, memo: String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("プレビュー（\(rows.count)件）").font(.caption).foregroundStyle(.secondary)
            ForEach(Array(rows.prefix(10).enumerated()), id: \.offset) { _, r in
                HStack(spacing: 8) {
                    Rectangle().fill(Color(hex: color)).frame(width: 3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        if !r.memo.isEmpty {
                            Text(r.memo).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            if rows.count > 10 {
                Text("他 \(rows.count - 10) 件...").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
