import SwiftUI

/// スワイプで出す削除ボタンの見た目。行の高さにかかわらず、ゴミ箱と「削除」を横に並べる。
/// swipeActions はラベルスタイルを無視して、行が高いと縦並びにするので、文字の中にゴミ箱を入れて 1 つの文字にする
let swipeDeleteLabel = Text("\(Image(systemName: "trash")) 削除")
