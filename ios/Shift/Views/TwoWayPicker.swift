import SwiftUI

/// 2択の切り替え。見た目は、いつもの分割ボタン(セグメント)のままで、どこをタップしても、もう一方に切り替わる
/// (3択以上は、これまでどおり押した選択肢を選ぶ)
struct TwoWayPicker<V: Hashable>: View {
    let title: String
    @Binding var selection: V
    let first: (label: String, value: V)
    let second: (label: String, value: V)

    @Environment(\.isEnabled) private var isEnabled

    init(_ title: String, selection: Binding<V>, first: (String, V), second: (String, V)) {
        self.title = title
        self._selection = selection
        self.first = (first.0, first.1)
        self.second = (second.0, second.1)
    }

    private var onFirst: Bool { selection == first.value }

    private func flip() {
        guard isEnabled else { return }
        selection = onFirst ? second.value : first.value
        UISelectionFeedbackGenerator().selectionChanged()
    }

    var body: some View {
        Picker(title, selection: $selection) {
            Text(first.label).tag(first.value)
            Text(second.label).tag(second.value)
        }
        .pickerStyle(.segmented)
        // 押した側ではなく、タップで切り替える(分割ボタン自身のタップは受けない)
        .allowsHitTesting(false)
        .overlay {
            Color.clear.contentShape(Rectangle()).onTapGesture { flip() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(onFirst ? first.label : second.label)
        .accessibilityHint("タップで切り替え")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { flip() }
    }
}
