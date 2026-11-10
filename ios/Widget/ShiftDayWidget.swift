import SwiftUI
import WidgetKit
import AppIntents

struct SmallDayView: View {
    let content: DayContent
    let offset: Int

    private var lineCap: Int {
        let n = content.events.count
        if content.pay != nil { return n <= 3 ? n : 3 }
        return n <= 4 ? n : 4
    }

    var body: some View {
        let shown = Array(content.events.prefix(lineCap))
        let rest = content.events.count - shown.count
        let compact = content.events.count >= 3
        VStack(alignment: .leading, spacing: 0) {
            header
            if let pay = content.pay {
                Text(pay)
                    .font(.app(10, weight: .semibold))
                    .foregroundStyle(Theme.payText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Theme.payFill))
                    .padding(.top, 3)
            }
            if content.events.isEmpty {
                Spacer(minLength: 0)
                Text("予定なし")
                    .font(.app(12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            } else {
                VStack(alignment: .leading, spacing: compact ? 2 : 3) {
                    ForEach(shown) { line in
                        EventLineView(line: line, compact: compact)
                    }
                    if rest > 0 {
                        Text("ほか\(rest)件")
                            .font(.app(10))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 8)
                    }
                }
                .padding(.top, 5)
                Spacer(minLength: 0)
            }
            nav
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .widgetURL(widgetDayURL(content.date, calendarId: content.calendarId))
    }

    private var header: some View {
        let p = Rules.ymd(content.date)
        return HStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(p.month)/\(p.day)").font(.app(13, weight: .bold))
                Text("(\(content.weekday))")
                    .font(.app(11, weight: .semibold))
                    .foregroundStyle(content.weekdayType.color)
            }
            .lineLimit(1)
            if !content.annivs.isEmpty {
                HStack(spacing: 2) {
                    ForEach(content.annivs) { a in
                        Image(a.asset)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 11, height: 11)
                            .foregroundStyle(Color(hex: a.color))
                    }
                }
                .fixedSize()
            }
            Spacer(minLength: 0)
            if let a = content.alarm {
                Text("🔔 \(a.first)" + (a.more > 0 ? " +\(a.more)" : ""))
                    .font(.app(10, weight: .semibold))
                    .foregroundStyle(Theme.alarm)
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Theme.alarm.opacity(0.16)))
            }
        }
        .frame(height: 18)
    }

    private var nav: some View {
        HStack {
            Button(intent: StepDayIntent(delta: -1)) { WidgetStepButtonLabel(systemName: "chevron.left") }
                .buttonStyle(.plain)
            Spacer()
            if offset != 0 {
                Button(intent: ResetDayIntent()) { WidgetBackLabel(text: "今日へ") }
                    .buttonStyle(.plain)
            } else {
                Text("今日")
                    .font(.app(10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(intent: StepDayIntent(delta: 1)) { WidgetStepButtonLabel(systemName: "chevron.right") }
                .buttonStyle(.plain)
        }
        .frame(height: 22)
    }
}

/// 共有した人のアイコン(丸)。写真・絵文字・頭文字を、アプリと同じ見た目で出す
struct WidgetOwnerAvatar: View {
    let owner: DayOwner
    let size: CGFloat

    var body: some View {
        if let photo = AvatarStyle.photo(from: owner.avatar) {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            let custom = AvatarStyle.customBackground(owner.avatar)
            let showsInitial = owner.avatar.isEmpty || custom != nil
            Text(showsInitial ? AvatarStyle.initial(of: owner.name) : owner.avatar)
                .font(.system(size: size * (showsInitial ? 0.5 : 0.6), weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: size, height: size)
                .background(Circle().fill(Color(hex: custom ?? AvatarStyle.color(for: owner.uid))))
        }
    }
}

/// 共有カレンダーのアイコン(丸)。写真なら丸く切り取り、記号なら予定の色の丸の中に出す
struct WidgetAvatar: View {
    let icon: String
    let color: Color
    let size: CGFloat

    var body: some View {
        if let photo = AvatarStyle.photo(from: icon) {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            // アイコンの名前に色("名前|#rrggbb")が付いていることがあるので、名前だけを使う
            Image(systemName: icon.components(separatedBy: "|").first ?? icon)
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.white.opacity(0.6)))
        }
    }
}

/// 予定1件。予定の色で名前と時間を囲む。1〜2件は2行、3件以上は1行に詰める
struct EventLineView: View {
    let line: DayEventLine
    let compact: Bool

    var body: some View {
        let color = EventColor.text(line.color)
        HStack(spacing: 6) {
            // 共有した人(共有カレンダーの中で作った予定は、共有カレンダー)のアイコンは、バーの一番左に、バーに収まる大きさで出す
            if let owner = line.owner { WidgetOwnerAvatar(owner: owner, size: compact ? 14 : 22) }
            else if let icon = line.icon { WidgetAvatar(icon: icon, color: color, size: compact ? 14 : 22) }
            Group {
            if compact {
                HStack(spacing: 6) {
                    Text(line.title)
                        .font(.app(11.5, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    sub(size: 9.5)
                }
                .padding(.vertical, 2)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text(line.title)
                        .font(.app(12, weight: .semibold))
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        sub(size: 10)
                    }
                }
                .padding(.vertical, 4)
            }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EventColor.fill(line.color), in: RoundedRectangle(cornerRadius: 8))
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func sub(size: CGFloat) -> some View {
        if line.showsTime {
            FixedWidthTimeText(text: line.label, size: size, weight: .medium)
        } else if !line.label.isEmpty {
            Text(line.label).font(.app(size)).lineLimit(1)
        }
    }
}
