import SwiftUI
import UIKit

struct UnplacedArea: View {
    @Environment(Store.self) private var store
    let anchor: String
    let onSelectEvent: (ShiftEvent) -> Void

    @AppStorage("unplacedCollapsed") private var collapsed = false
    @State private var confirmRecall = false
    @State private var backTargeted = false

    private var monthLabel: String {
        let p = Rules.ymd(anchor)
        return String(format: "%04d/%02d", p.year, p.month)
    }

    var body: some View {
        let items = store.unplacedEvents
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("未配置").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                Text("\(items.count)")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .background(Color(.tertiarySystemFill), in: Capsule())
                Button("\(monthLabel)を回収") { confirmRecall = true }
                    .font(.caption2)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                Button("並び替え") {
                    withAnimation(.snappy) { store.sortUnplaced() }
                }
                .font(.caption2)
                .buttonStyle(.bordered)
                .controlSize(.mini)
                Spacer()
                Button {
                    withAnimation(.snappy) { collapsed.toggle() }
                } label: {
                    Image(systemName: collapsed ? "chevron.up" : "chevron.down").font(.caption)
                        .padding(4).contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            if !collapsed {
                Divider()
                HStack(spacing: 0) {
                    ScrollView {
                        if items.isEmpty {
                            Text("すべて配置済みです")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 24)
                        } else {
                            FlowLayout(spacing: 6) {
                                ForEach(items) { chip($0) }
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    backZone
                }
                .frame(height: 120)
            }
        }
        .background(Color(.secondarySystemBackground))
        .confirmationDialog("\(monthLabel)の配置済み予定をすべて未配置に戻しますか?",
                            isPresented: $confirmRecall, titleVisibility: .visible) {
            Button("未配置に戻す", role: .destructive) {
                withAnimation(.snappy) { _ = store.recallMonth(of: anchor) }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        }
    }

    private func chip(_ ev: ShiftEvent) -> some View {
        let color = Color(hex: ev.color)
        let time = Rules.timeLabel(ev)
        return HStack(spacing: 4) {
            Text(ev.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(color).lineLimit(1)
            if !time.isEmpty {
                Text(time).font(.system(size: 9)).foregroundStyle(color.opacity(0.7))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(color.opacity(0.16))
        .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: 3) }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture { onSelectEvent(ev) }
        .draggable(ev.id)
    }

    private var backZone: some View {
        VStack(spacing: 2) {
            Image(systemName: "tray.and.arrow.down").font(.title3)
            Text("未配置\nに戻す").font(.system(size: 9)).multilineTextAlignment(.center)
        }
        .foregroundStyle(backTargeted ? Theme.accent : Color.secondary)
        .frame(width: 72)
        .frame(maxHeight: .infinity)
        .background(backTargeted ? Theme.accent.opacity(0.12) : Color(.tertiarySystemFill))
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first else { return false }
            withAnimation(.snappy) { store.unplace(id: id) }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            return true
        } isTargeted: { backTargeted = $0 }
    }
}
