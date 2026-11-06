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
    @Environment(Store.self) private var store
    @Environment(SharedViewState.self) private var sharedView
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var avatar = ""
    @FocusState private var nameFocused: Bool
    /// 誕生日(登録すると、誕生日・記念日に自動で入る)
    @State private var hasBirthday = false
    @State private var knowsYear = false
    @State private var birthYear = 2000
    @State private var birthMonth = 1
    @State private var birthDay = 1

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
                Section {
                    Toggle("誕生日を登録", isOn: $hasBirthday)
                    if hasBirthday {
                        Toggle("生まれ年も入力", isOn: $knowsYear)
                        if knowsYear {
                            Picker("年", selection: $birthYear) {
                                ForEach((1900...Rules.ymd(Rules.today()).year).reversed(), id: \.self) { Text("\($0)年").tag($0) }
                            }
                        }
                        Picker("月", selection: $birthMonth) {
                            ForEach(1...12, id: \.self) { Text("\($0)月").tag($0) }
                        }
                        Picker("日", selection: $birthDay) {
                            ForEach(1...31, id: \.self) { Text("\($0)日").tag($0) }
                        }
                    }
                } header: {
                    Text("誕生日")
                } footer: {
                    Text("登録すると、設定の「記念日・誕生日」に、自分の誕生日として自動で入ります。変えられるのは、ここだけです(記念日・誕生日の画面では、アイコンと色だけ変えられます)。共有カレンダーにも、自分の誕生日として追加できます。")
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
                        // 自分の誕生日を、誕生日・記念日に入れる(名前を変えたときも、名前を合わせる)
                        if hasBirthday {
                            store.setMyBirthday(name: shownName, year: knowsYear ? birthYear : nil, month: birthMonth, day: birthDay)
                        } else {
                            store.clearMyBirthday()
                        }
                        // 共有カレンダーに入れてある自分の誕生日も、合わせる
                        let mine = store.myBirthday
                        let shared = sharedView
                        Task { await shared.syncMyBirthday(mine) }
                        dismiss()
                    }
                }
            }
            .keyboardDismissBar { nameFocused = false }
            .onAppear {
                name = profile.customName
                avatar = profile.avatar
                if let b = store.myBirthday {
                    hasBirthday = true
                    knowsYear = b.year != nil
                    birthYear = b.year ?? 2000
                    birthMonth = b.month
                    birthDay = b.day
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Color(.systemGroupedBackground))
    }
}
