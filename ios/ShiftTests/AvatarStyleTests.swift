import Foundation
import Testing
import UIKit
@testable import Shift

struct AvatarStyleTests {
    @Test func colorIsStableAndInitialTakesTheFirstCharacter() {
        #expect(AvatarStyle.color(for: "abc") == AvatarStyle.color(for: "abc"))
        #expect(AvatarStyle.palette.contains(AvatarStyle.color(for: "someone")))
        #expect(AvatarStyle.initial(of: " ゆうき") == "ゆ")
        #expect(AvatarStyle.initial(of: "  ") == "?")
    }

    @Test func customBackgroundAndPhotoAreToldApart() {
        #expect(AvatarStyle.customBackground("bg:#ff0000") == "#ff0000")
        #expect(AvatarStyle.customBackground("🙂") == nil)
        #expect(AvatarStyle.photo(from: "🙂") == nil)
        #expect(AvatarStyle.photo(from: "img:not-base64!!") == nil)
        let size = CGSize(width: 4, height: 4)
        let jpeg = UIGraphicsImageRenderer(size: size).jpegData(withCompressionQuality: 0.8) { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        #expect(AvatarStyle.photo(from: "img:" + jpeg.base64EncodedString()) != nil)
        // アプリ側の UserAvatar と同じ結果になる
        #expect(UserAvatar.color(for: "abc") == AvatarStyle.color(for: "abc"))
    }
}
