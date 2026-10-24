import SwiftUI

struct DaySheet: View {
    @Environment(Store.self) private var store
    @Environment(Holidays.self) private var holidays
    @Environment(\.dismiss) private var dismiss

    let date: String
    let onSelectEvent: (ShiftEvent) -> Void

    private var dateText: String {
        let p = Rules.ymd(date)
        let wd = Rules.weekdayLabels(startMonday: false)[Rules.weekday(date)]
        return "\(p.year)年\(p.month)月\(p.day)日 (\(wd))"
    }

    var body: some View {
        let summary = store.daySummary(date: date, isHoliday: { holidays.name(on: $0) != nil })
        NavigationStack {
            VStack(spacing: 0) {
                Text(dateText)
                    .font(.app(14))
                    .foregroundStyle(Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color(.secondarySystemBackground))
                if summary.paydays.isEmpty && summary.events.isEmpty {
                    Spacer()
                    Text("予定はありません")
                        .foregroundStyle(Color.secondary)
                    Spacer()
                } else {
                    List {
                        ForEach(summary.paydays) { r in
                            paydayRow(r)
                        }
                        ForEach(summary.events) { row in
                            Button {
                                dismiss()
                                onSelectEvent(row.event)
                            } label: {
                                eventRow(row)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func paydayRow(_ r: Store.PaymentRow) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text("給料日")
                .font(.app(13, weight: .bold))
                .foregroundStyle(Theme.payText)
                .frame(width: 64, alignment: .trailing)
            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.payText.opacity(0.7))
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(Money.yen(r.amount))
                    .font(.app(17, weight: .bold))
                    .foregroundStyle(Theme.payText)
                Text(r.workplace.name)
                    .font(.app(17))
                    .foregroundStyle(Color.primary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private func eventRow(_ row: DayEventRow) -> some View {
        let ev = row.event
        return HStack(alignment: .center, spacing: 8) {
            timeColumn(row)
                .frame(width: 64, alignment: .trailing)
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: ev.color))
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(ev.title)
                    .font(.app(17))
                    .foregroundStyle(Color.primary)
                if !ev.memo.isEmpty {
                    Text(ev.memo)
                        .font(.app(12))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func timeColumn(_ row: DayEventRow) -> some View {
        let ev = row.event
        if row.isAllDay {
            Text("終日")
                .font(.app(16))
                .foregroundStyle(Color.primary)
        } else if row.isContinuation {
            VStack(alignment: .trailing, spacing: 2) {
                Text("前日から")
                    .font(.app(11))
                    .foregroundStyle(Color.secondary)
                if let e = ev.endTime {
                    Text(e)
                        .font(.app(14).monospacedDigit())
                        .foregroundStyle(Color.secondary)
                }
            }
        } else {
            VStack(alignment: .trailing, spacing: 2) {
                Text(ev.startTime ?? "")
                    .font(.app(16).monospacedDigit())
                    .foregroundStyle(Color.primary)
                if let e = ev.endTime {
                    Text(e)
                        .font(.app(14).monospacedDigit())
                        .foregroundStyle(Color.secondary)
                }
            }
        }
    }
}
