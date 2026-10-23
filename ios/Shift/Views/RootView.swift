import SwiftUI
import UIKit

enum CalendarMode: String { case week, month }

struct EditorTarget: Identifiable {
    let event: ShiftEvent
    let isNew: Bool
    var id: String { event.id }
}

struct CSVFile: Identifiable {
    let url: URL
    var id: URL { url }
}

/// 一括取り込み画面ができるまでの仮の表示(次のタスクで BulkImportSheet に置き換える)
private struct BulkImportPlaceholder: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Text("準備中")
                .navigationTitle("一括取り込み")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } }
                }
        }
    }
}

struct RootView: View {
    @Environment(Store.self) private var store
    @Environment(Holidays.self) private var holidays
    @AppStorage("mode") private var mode: CalendarMode = .week
    @AppStorage("startMonday") private var startMonday = false
    @AppStorage("showSummary") private var showSummary = 0   // 0 なし / 1 週計 / 2 月計

    @State private var anchor = Rules.today()
    @State private var editing: EditorTarget?
    @State private var showDrawer = false
    @State private var showSettings = false
    @State private var showBulkImport = false
    @State private var csvFile: CSVFile?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Group {
                switch mode {
                case .month:
                    MonthView(anchor: anchor, startMonday: startMonday, summaryMode: showSummary, onSelectDay: addEvent, onSelectEvent: edit, onDropEvent: drop)
                case .week:
                    WeekView(anchor: anchor, startMonday: startMonday, summaryMode: showSummary, onSelectDay: addEvent, onSelectEvent: edit, onDropEvent: drop)
                }
            }
            .id(mode)
            .transition(.opacity)
            .contentShape(Rectangle())
            .simultaneousGesture(swipe)
            UnplacedArea(anchor: anchor, onSelectEvent: edit)
        }
        .task(id: Rules.ymd(anchor).year) { await holidays.load(around: Rules.ymd(anchor).year) }
        .sheet(item: $editing) { EventEditor(original: $0.event, isNew: $0.isNew) }
        .sheet(isPresented: $showDrawer) {
            DrawerSheet(
                anchor: anchor,
                onEdit: { ev in fromDrawer { edit(ev) } },
                onAddUnplaced: { fromDrawer { addUnplaced() } },
                onBulkImport: { fromDrawer { showBulkImport = true } },
                onSettings: { fromDrawer { showSettings = true } })
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showBulkImport) { BulkImportPlaceholder() }
        .sheet(item: $csvFile) { ShareSheet(items: [$0.url]) }
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button { showDrawer = true } label: {
                    Image(systemName: "line.3.horizontal").font(.title3)
                }
                Spacer(minLength: 0)
                Button { step(-1) } label: { Image(systemName: "chevron.left") }
                Text(title).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                Button { step(1) } label: { Image(systemName: "chevron.right") }
                Spacer(minLength: 0)
                Button { addUnplaced() } label: {
                    Text("＋ 追加")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Theme.accent, in: Capsule())
                }
            }
            HStack(spacing: 10) {
                Picker("表示", selection: $mode.animation(.snappy)) {
                    Text("週").tag(CalendarMode.week)
                    Text("月").tag(CalendarMode.month)
                }
                .pickerStyle(.segmented)
                .frame(width: 110)
                Button("今日") { withAnimation(.snappy) { anchor = Rules.today() } }
                    .font(.subheadline)
                Button(startMonday ? "月始" : "日始") { startMonday.toggle() }
                    .font(.subheadline)
                Spacer(minLength: 0)
                Button { showSummary = (showSummary + 1) % 3 } label: {
                    Text(["集計", "週計", "月計"][showSummary])
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(showSummary > 0 ? Theme.accentSoft : Color.clear, in: Capsule())
                        .overlay(Capsule().stroke(showSummary > 0 ? Theme.accent : Color.secondary.opacity(0.4)))
                }
                Button("CSV") { exportCSV() }
                    .font(.caption.weight(.medium))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var title: String {
        if mode == .month {
            let p = Rules.ymd(anchor)
            return "\(p.year)年\(p.month)月"
        }
        let s = Rules.weekStart(of: anchor, startMonday: startMonday)
        let sp = Rules.ymd(s), ep = Rules.ymd(Rules.addDays(s, 6))
        return sp.month == ep.month
            ? "\(sp.year)年\(sp.month)月\(sp.day)〜\(ep.day)日"
            : "\(sp.month)月\(sp.day)日〜\(ep.month)月\(ep.day)日"
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 30).onEnded { v in
            guard abs(v.translation.width) > 60, abs(v.translation.width) > abs(v.translation.height) * 1.5 else { return }
            step(v.translation.width < 0 ? 1 : -1)
        }
    }

    private func step(_ n: Int) {
        withAnimation(.snappy) {
            anchor = mode == .month ? Rules.addMonths(anchor, n) : Rules.addDays(anchor, 7 * n)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func addEvent(on date: String) {
        editing = EditorTarget(event: .new(on: date), isNew: true)
    }

    private func addUnplaced() {
        editing = EditorTarget(event: .newUnplaced(), isNew: true)
    }

    private func edit(_ event: ShiftEvent) {
        editing = EditorTarget(event: event, isNew: false)
    }

    /// ドロワーを閉じてから次のシートを開く(シートの同時表示を避ける)
    private func fromDrawer(_ next: @escaping () -> Void) {
        showDrawer = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: next)
    }

    private func exportCSV() {
        let text = CSVExport.make(events: store.events, month: anchor)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(CSVExport.fileName(for: anchor))
        do {
            try Data(text.utf8).write(to: url, options: .atomic)
            csvFile = CSVFile(url: url)
        } catch {}
    }

    private func drop(id: String, on date: String) {
        withAnimation(.snappy) { store.place(id: id, on: date) }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}
