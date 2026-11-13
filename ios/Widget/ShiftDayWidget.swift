import SwiftUI
import WidgetKit
import AppIntents

struct SmallDayView: View {
    let content: DayContent
    let offset: Int

    private var lineCap: Int {
        let n = content.events.count
        if hasSubRow { return n <= 3 ? n : 3 }
        return n <= 4 ? n : 4
    }

    var body: some View {
        let shown = Array(content.events.prefix(lineCap))
        let rest = content.events.count - shown.count
        let compact = content.events.count >= 3
        VStack(alignment: .leading, spacing: 0) {
            header
            if content.events.isEmpty {
                Spacer(minLength: 0)
                Text("予定なし")
                    .font(.app(12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            } else {
                // 予定の行は、日付の下から「前へ・次へ」ボタンの上までの空きを、ぴったり使い切る高さにする(自動)。
                // 1 件のときだけは、2 件のときの 1 行と同じ高さにする(空の 2 行目を置いて、同じ割り方にする)
                VStack(alignment: .leading, spacing: compact ? 2 : 3) {
                    ForEach(shown) { line in
                        EventLineView(line: line, compact: compact, stretch: true)
                    }
                    if shown.count == 1 {
                        Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    if rest > 0 {
                        Text("ほか\(rest)件")
                            .font(.app(11))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.trailing, 8)
                            // 「ほか」の行だけ、下の余白を 3pt 詰めて、矢印ボタンに近づける
                            .padding(.bottom, -3)
                    }
                }
                .frame(maxHeight: .infinity)
                // 下の矢印ボタンに接しないよう、少し空ける
                .padding(.bottom, 6)
                // 日付の下の行(給料日・アラーム)があるときは、その行と1つ目の予定の間を、予定どうしの間と同じにする
                .padding(.top, hasSubRow ? (compact ? 2 : 3) : 5)
                Spacer(minLength: 0)
            }
            nav
        }
        .padding(.horizontal, 11)
        .padding(.top, 11)
        .padding(.bottom, 8)
        .widgetURL(widgetDayURL(content.date, calendarId: content.calendarId))
    }

    /// 日付の下の行(給料日・アラーム)があるか
    private var hasSubRow: Bool { content.pay != nil || content.alarm != nil }

    /// 日付の行。日付と曜日の右に記念日のアイコン(2 個まで、3 個目からは「+n」)。
    /// その下の行に、給料日(左)とアラーム(右)を出す
    private var header: some View {
        let p = Rules.ymd(content.date)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(p.month)/\(p.day)").font(.app(17, weight: .bold))
                    Text("(\(content.weekday))")
                        .font(.app(10, weight: .semibold))
                        .foregroundStyle(content.weekdayType.color)
                }
                .lineLimit(1)
                if !content.annivs.isEmpty {
                    HStack(spacing: 2) {
                        ForEach(content.annivs.prefix(2)) { a in
                            Image(a.asset)
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 11, height: 11)
                                .foregroundStyle(Color(hex: a.color))
                        }
                        if content.annivs.count > 2 {
                            Text("+\(content.annivs.count - 2)")
                                .font(.app(9, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .fixedSize()
                }
                Spacer(minLength: 0)
                // 右上: カレンダーの切り替え(2 つ以上選んでいるときだけ)
                if let sw = content.switcher {
                    Button(intent: CycleCalendarIntent(size: "small")) { WidgetCalendarSwitchLabel(sw: sw, size: 19, badge: 9) }
                        .buttonStyle(.plain)
                }
            }
            .frame(height: 18)
            if hasSubRow {
                HStack(spacing: 4) {
                    if let pay = content.pay {
                        HStack(spacing: 3) {
                            Image("CoinStack")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 11, height: 11)
                                .foregroundStyle(Color(red: 0.95, green: 0.7, blue: 0.1))
                            Text(pay)
                                .font(.app(9.5, weight: .semibold))
                                .foregroundStyle(Theme.payText)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Theme.payFill))
                        .fixedSize()
                    }
                    if let a = content.alarm {
                        // ベルと時刻だけを角丸の四角で囲み、「+2」は囲みの外に出す(カレンダーと同じベル bell.fill)
                        HStack(spacing: 2) {
                            HStack(spacing: 1) {
                                Image(systemName: "bell.fill").font(.app(11))
                                Text(a.first)
                                    .font(.app(10, weight: .semibold))
                                    .lineLimit(1)
                            }
                            .padding(.leading, 2)
                            .padding(.trailing, 3)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 5).fill(Theme.alarm.opacity(0.16)))
                            if a.more > 0 {
                                Text("+\(a.more)")
                                    .font(.app(10, weight: .semibold))
                                    .lineLimit(1)
                            }
                        }
                        .foregroundStyle(Theme.alarm)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 3)
            }
        }
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
            // アイコンの名前に色("名前|#rrggbb")が付いていることがある。付いていれば、その色で出す
            let parts = icon.components(separatedBy: "|")
            let tint = parts.count > 1 && parts[1].hasPrefix("#") ? Color(hex: parts[1]) : color
            Image(systemName: parts.first ?? icon)
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.white.opacity(0.6)))
        }
    }
}

/// 予定1件。予定の色で名前と時間を囲む。1〜2件は2行、3件以上は1行に詰める
struct EventLineView: View {
    let line: DayEventLine
    let compact: Bool
    /// 行を縦に広げる(中の文字は行の真ん中)
    var stretch: Bool = false

    /// 共有アイコンがあって、タイトルが隠れてしまうときは、文字を小さくして収める(7 文字ぶんが入る 0.65 倍まで)
    private var titleScale: CGFloat { (line.owner != nil || line.icon != nil) ? 0.65 : 1 }

    var body: some View {
        let color = EventColor.text(line.color)
        // 3 件以上(1 行)で共有アイコンがあるときは、アイコンの左右の隙間を詰めて、タイトルを広く見せる
        let tightAvatar = compact && (line.owner != nil || line.icon != nil)
        HStack(spacing: tightAvatar ? 3 : 6) {
            // 共有した人(共有カレンダーの中で作った予定は、共有カレンダー)のアイコンは、バーの一番左に、バーに収まる大きさで出す
            if let owner = line.owner { WidgetOwnerAvatar(owner: owner, size: compact ? 14 : 22) }
            else if let icon = line.icon { WidgetAvatar(icon: icon, color: color, size: compact ? 14 : 22) }
            Group {
            if compact {
                // 行の高さは、中身の文字(開始・締切の記号や等幅の時刻)に左右されないよう固定する
                // タイトルと時刻の間は、最低 4pt(以前は 12pt)まで詰めて、タイトルを広く使う
                HStack(spacing: 2) {
                    Text(line.title)
                        .font(.app(11.5, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(titleScale)
                    Spacer(minLength: 0)
                    sub(size: 9.5)
                }
                .frame(height: stretch ? nil : 16)
                .padding(.vertical, 2)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text(line.title)
                        .font(.app(12, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(titleScale)
                        .frame(height: 16, alignment: .leading)
                    HStack(spacing: 4) {
                        sub(size: 10)
                    }
                    .frame(height: 13, alignment: .leading)
                    // 時刻・終日の行は、少し上げる(2 件のとき、下に空きがあるため)
                    .offset(y: -4)
                }
                .padding(.vertical, 3)
            }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(color)
        .padding(.leading, line.taskStart == false ? 12 : (tightAvatar ? 4 : 8))
        .padding(.trailing, line.taskStart == true ? 12 : 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: stretch ? .infinity : nil)
        .background { lineBackground }
    }

    /// 予定は角丸の帯。開始・締切は、カレンダーと同じ矢印形(開始は白抜きで右向き、締切は塗りで左向き)
    @ViewBuilder
    private var lineBackground: some View {
        if let isStart = line.taskStart {
            let shape = ArrowTagShape(pointsRight: isStart, notch: 7)
            shape.fill(isStart ? Color(.systemBackground) : EventColor.fill(line.color))
                .overlay { if isStart { shape.stroke(Color(hex: line.color), lineWidth: 1.2) } }
        } else {
            RoundedRectangle(cornerRadius: 8).fill(EventColor.fill(line.color))
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8))
        }
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
