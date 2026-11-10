import SwiftUI

/// キーボードの上に、キーボードを閉じるボタンの帯を出す。
/// ツールバーの .keyboard は、フォーカスの移り方によって出ないことがあるので、キーボードの出入りを見て自分で出す
private struct KeyboardDismissBar: ViewModifier {
    /// 左に出す、もう 1 つのボタン(例: 時間の「指定なし」)。nil なら出さない
    var leading: (title: String, action: () -> Void)?
    let onClose: () -> Void
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if visible {
                    HStack {
                        if let leading {
                            Button(leading.title, action: leading.action)
                                .font(.app(15, weight: .semibold))
                                .frame(minHeight: 40)
                                .padding(.horizontal, 8)
                        }
                        Spacer()
                        Button {
                            onClose()
                            // 画面が持っていない入力欄(メモ・URL など、部品の中で管理している欄)も、閉じる
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        } label: {
                            Image(systemName: "keyboard.chevron.compact.down")
                                .font(.title3)
                                .frame(minWidth: 44, minHeight: 40)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("キーボードを閉じる")
                    }
                    .padding(.horizontal, 8)
                    .background(.bar)
                    .overlay(alignment: .top) { Divider() }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                visible = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                visible = false
            }
    }
}

extension View {
    /// キーボードが出ている間、その上に閉じるボタンを出す
    func keyboardDismissBar(onClose: @escaping () -> Void) -> some View {
        modifier(KeyboardDismissBar(onClose: onClose))
    }

    /// 左にも 1 つボタンを出す(nil なら出さない)
    func keyboardDismissBar(leading: (title: String, action: () -> Void)?, onClose: @escaping () -> Void) -> some View {
        modifier(KeyboardDismissBar(leading: leading, onClose: onClose))
    }

    /// フォーカスの管理をしていない画面用。いま文字を入力している欄を閉じる
    func keyboardDismissBar() -> some View {
        keyboardDismissBar {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
}
