import SwiftUI

/// キーボードの上に、キーボードを閉じるボタンの帯を出す。
/// ツールバーの .keyboard は、フォーカスの移り方によって出ないことがあるので、キーボードの出入りを見て自分で出す
private struct KeyboardDismissBar: ViewModifier {
    let onClose: () -> Void
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if visible {
                    HStack {
                        Spacer()
                        Button(action: onClose) {
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

    /// フォーカスの管理をしていない画面用。いま文字を入力している欄を閉じる
    func keyboardDismissBar() -> some View {
        keyboardDismissBar {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
}
