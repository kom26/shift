import SwiftUI

/// スワイプで出す削除ボタンの見た目。行の高さにかかわらず、ゴミ箱と「削除」を横に並べる
struct SwipeDeleteLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
            configuration.title
        }
    }
}
