import Foundation
import Testing
@testable import Shift

struct FirstTutorialTests {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: UUID().uuidString)! }

    @Test func showsUntilStartIsPressed() {
        #expect(FirstTutorial.shouldShow(defaults: defaults(), hasInvite: false))
    }

    @Test func hiddenOnceDone() {
        let d = defaults()
        d.set(true, forKey: FirstTutorial.doneKey)
        #expect(!FirstTutorial.shouldShow(defaults: d, hasInvite: false))
    }

    @Test func hiddenWhileAnInviteIsWaiting() {
        #expect(!FirstTutorial.shouldShow(defaults: defaults(), hasInvite: true))
    }

    @Test func doneFlagIsSyncedAndNotClearedByAccountWithoutIt() {
        let d = defaults()
        d.set(true, forKey: FirstTutorial.doneKey)
        // アカウントに印が無くても、この端末で見たあとなら、戻さない
        SyncedPrefs.write([:], to: d)
        #expect(d.bool(forKey: FirstTutorial.doneKey))
        // 預ける対象に入っている(アカウントを結びつけたら、保存される)
        #expect(SyncedPrefs.read(d)[FirstTutorial.doneKey] == "b:1")
        // 別の端末で見ていたら、この端末にも入る
        let other = defaults()
        SyncedPrefs.write(["tutorialDone": "b:1"], to: other)
        #expect(other.bool(forKey: FirstTutorial.doneKey))
    }
}
