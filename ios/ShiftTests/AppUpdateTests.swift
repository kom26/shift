import Foundation
import Testing
@testable import Shift

struct AppUpdateTests {
    private func config(latest: Int, min: Int = 0, mode: UpdateConfig.Mode = .soft) -> UpdateConfig {
        UpdateConfig(latestBuild: latest, minBuild: min, mode: mode, storeUrl: nil)
    }

    @Test func noConfigShowsNothing() {
        #expect(UpdateAction.decide(build: 10, config: nil) == .none)
    }

    @Test func olderThanLatestFollowsMode() {
        #expect(UpdateAction.decide(build: 45, config: config(latest: 48, mode: .soft)) == .soft)
        #expect(UpdateAction.decide(build: 45, config: config(latest: 48, mode: .force)) == .force)
        #expect(UpdateAction.decide(build: 45, config: config(latest: 48, mode: .none)) == .none)
    }

    @Test func newerOrEqualBuildShowsNothing() {
        // 外部に配られなかった途中のビルドを持っている人にも、案内は出ない
        #expect(UpdateAction.decide(build: 48, config: config(latest: 48)) == .none)
        #expect(UpdateAction.decide(build: 47, config: config(latest: 45)) == .none)
    }

    @Test func belowMinimumIsAlwaysForced() {
        #expect(UpdateAction.decide(build: 39, config: config(latest: 48, min: 40, mode: .soft)) == .force)
        #expect(UpdateAction.decide(build: 39, config: config(latest: 48, min: 40, mode: .none)) == .force)
        #expect(UpdateAction.decide(build: 40, config: config(latest: 48, min: 40, mode: .none)) == .none)
    }
}
