import SwiftUI

/// 2択の切り替え。見た目は分割ボタンだが、どこをタップしても、もう一方に切り替わる
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

    var body: some View {
        Button {
            selection = onFirst ? second.value : first.value
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack(spacing: 0) {
                segment(first.label, selected: onFirst)
                segment(second.label, selected: !onFirst)
            }
            .padding(2)
            .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 9))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.borderless)
        .animation(.snappy(duration: 0.18), value: onFirst)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(onFirst ? first.label : second.label)
        .accessibilityHint("タップで切り替え")
        .accessibilityAddTraits(.isButton)
    }

    private func segment(_ text: String, selected: Bool) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity, minHeight: 28)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.12), radius: 1.5, y: 1)
                }
            }
    }
}
