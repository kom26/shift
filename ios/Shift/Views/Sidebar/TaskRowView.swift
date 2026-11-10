import SwiftUI

/// 予定一覧と管理画面に出す、開始・締切・タスクの 1 行。チェックは右端の角丸の四角で、付けると取消線になる
struct TaskRowView: View {
    let row: TaskRow
    let onToggle: () -> Void

    var body: some View {
        let t = row.task
        HStack(alignment: .center, spacing: 8) {
            if row.isStart != nil {
                timeColumn
                    .frame(width: 64, alignment: .trailing)
                RoundedRectangle(cornerRadius: 2)
                    .fill(EventColor.fill(t.color))
                    .frame(width: 4)
                    .opacity(t.done ? 0.4 : 1)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(t.title.isEmpty ? "(タイトルなし)" : t.title)
                    .font(.app(17))
                    .strikethrough(t.done)
                    .foregroundStyle(t.done ? Color.secondary : Color.primary)
                if let sub = subText {
                    Text(sub.text)
                        .font(.app(12))
                        .foregroundStyle(sub.late ? Theme.sunday : Color.secondary)
                }
            }
            Spacer(minLength: 0)
            checkbox
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var timeColumn: some View {
        let t = row.task
        let label = row.isStart == true ? "開始" : "締切"
        return VStack(alignment: .trailing, spacing: 2) {
            if let time = row.time {
                Text(time)
                    .font(.app(16).monospacedDigit())
                    .foregroundStyle(t.done ? Color.secondary : Color.primary)
                Text(label)
                    .font(.app(11, weight: .semibold))
                    .foregroundStyle(EventColor.text(t.color))
            } else {
                Text(label)
                    .font(.app(14, weight: .semibold))
                    .foregroundStyle(EventColor.text(t.color))
            }
        }
        .opacity(t.done ? 0.5 : 1)
    }

    /// 名前の下の小さな文字: 期限切れ、または、もう片方の日付
    private var subText: (text: String, late: Bool)? {
        let t = row.task
        if row.isStart == false, !t.done, let due = t.dueDate, due < Rules.today() {
            return ("期限切れ", true)
        }
        if row.isStart == true, let due = t.dueDate {
            return ("締切 " + Self.short(due) + (t.dueTime.map { " " + $0 } ?? ""), false)
        }
        if row.isStart == false, let start = t.startDate {
            return ("開始 " + Self.short(start) + (t.startTime.map { " " + $0 } ?? ""), false)
        }
        return nil
    }

    static func short(_ ds: String) -> String {
        let p = Rules.ymd(ds)
        return "\(p.month)/\(p.day)"
    }

    private var checkbox: some View {
        let done = row.task.done
        return Button(action: onToggle) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(done ? Theme.accent : Color.clear)
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(done ? Theme.accent : Color.secondary.opacity(0.6), lineWidth: 1.6)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.onAccent)
                }
            }
            .frame(width: 24, height: 24)
            .padding(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(done ? "完了を外す" : "完了にする")
    }
}
