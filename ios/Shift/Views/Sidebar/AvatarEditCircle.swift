import PhotosUI
import SwiftUI

/// 名前の横の丸いアバター。頭文字のときは、タップして写真を選び、ピンチ・回転で範囲を合わせて決める。
/// 写真のときは、タップして「頭文字に戻す」か「写真を選び直す」を選べる
struct AvatarEditCircle: View {
    @Binding var avatar: String
    let uid: String
    /// 頭文字に使う名前(入力中の名前)
    let name: String
    var size: CGFloat = 52

    @State private var showPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var cropTarget: AvatarCropTarget?
    @State private var showOptions = false
    @State private var loadFailed = false

    private var isPhoto: Bool { AvatarPhoto.isPhoto(avatar) }

    var body: some View {
        Button {
            if isPhoto { showOptions = true } else { showPicker = true }
        } label: {
            UserAvatar(uid: uid, name: name, avatar: isPhoto ? avatar : "", size: size)
                .overlay(alignment: .bottomTrailing) {
                    if !isPhoto {
                        // 押すと写真を選べることを、小さなカメラで示す
                        Image(systemName: "camera.fill")
                            .font(.system(size: size * 0.2, weight: .bold))
                            .foregroundStyle(Theme.onAccent)
                            .frame(width: size * 0.36, height: size * 0.36)
                            .background(Theme.accent, in: Circle())
                            .offset(x: 2, y: 2)
                    }
                }
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(isPhoto ? "アバター(写真)。タップで変更" : "アバター(頭文字)。タップで写真を選ぶ")
        .photosPicker(isPresented: $showPicker, selection: $photoItem, matching: .images)
        .confirmationDialog("アバター", isPresented: $showOptions, titleVisibility: .hidden) {
            Button("写真を選び直す") { showPicker = true }
            Button("デフォルトに戻す(頭文字)", role: .destructive) { avatar = "" }
            Button("キャンセル", role: .cancel) {}
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    cropTarget = AvatarCropTarget(image: image)
                } else {
                    loadFailed = true
                }
                photoItem = nil
            }
        }
        .sheet(item: $cropTarget) { target in
            AvatarCropSheet(image: target.image) { square in
                if let encoded = AvatarPhoto.encode(square: square) { avatar = encoded }
            }
        }
        .alert("写真を読み込めませんでした", isPresented: $loadFailed) { Button("OK") {} }
    }
}

/// アカウントの「名前とアバター」を直す画面。ここで決めたものが、共有カレンダーを作る・参加するときの初期値になる
struct ProfileEditSheet: View {
    @Environment(ProfileSettings.self) private var profile
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var avatar = ""
    @FocusState private var nameFocused: Bool

    private var providerName: String { ProfileSettings.providerName(auth.account) }
    private var shownName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? providerName : trimmed
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        AvatarEditCircle(avatar: $avatar, uid: auth.account?.uid ?? "", name: shownName, size: 64)
                        TextField(providerName.isEmpty ? "名前" : providerName, text: $name)
                            .focused($nameFocused)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("名前とアバター")
                } footer: {
                    Text("アプリの中での表示です。共有カレンダーを作る・参加するときの、相手に見える名前とアバターの初期値になります。アバターは、最初は名前の頭文字で、丸をタップして写真にできます。")
                }
                if !name.trimmingCharacters(in: .whitespaces).isEmpty, !providerName.isEmpty {
                    Section {
                        Button("連携した名前(\(providerName))に戻す") { name = "" }
                    }
                }
            }
            .navigationTitle("名前とアバター")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        profile.customName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        profile.avatar = avatar
                        dismiss()
                    }
                }
            }
            .keyboardDismissBar { nameFocused = false }
            .onAppear {
                name = profile.customName
                avatar = profile.avatar
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Color(.systemGroupedBackground))
    }
}
