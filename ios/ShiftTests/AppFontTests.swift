import SwiftUI
import Testing
@testable import Shift

struct AppFontTests {
    @Test func weightMapping() {
        #expect(AppFont.name(for: .regular) == "ZenMaruGothic-Regular")
        #expect(AppFont.name(for: .medium) == "ZenMaruGothic-Medium")
        #expect(AppFont.name(for: .bold) == "ZenMaruGothic-Bold")
        #expect(AppFont.name(for: .semibold) == "ZenMaruGothic-Bold")
        #expect(AppFont.name(for: .light) == "ZenMaruGothic-Regular")
    }
}
