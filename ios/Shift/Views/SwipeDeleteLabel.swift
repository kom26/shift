import SwiftUI

/// スワイプで出す削除ボタンの見た目。ゴミ箱の記号と「削除」。
/// 以前は SF Symbols の「trash」の文字(U+100211)を文字の頭に置いていたが、端末によって「?」になったので、
/// 標準のラベル(記号つき)にした。swipeActions が、行の高さに合わせて並べる
let swipeDeleteLabel = Label("削除", systemImage: "trash")

/// スワイプ削除の色。真っ赤ではなく、少し柔らかい赤
let swipeDeleteTint = Color(hex: "#e2706a")
