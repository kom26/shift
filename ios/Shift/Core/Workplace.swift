import Foundation

/// タイトルと色のプリセット。予定とは紐づけず、選択時にタイトルと色をコピーする
struct Workplace: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var color: String
}
