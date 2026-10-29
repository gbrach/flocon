import Foundation
import Testing
@testable import Flocon

struct MusicTests {
    @Test func volumeLevelsStayQuiet() {
        let levels = MusicVolume.allCases.map(\.level)
        #expect(levels == levels.sorted())
        #expect(levels.allSatisfy { $0 > 0 && $0 <= 0.3 })
        #expect(MusicVolume.soft.level < MusicVolume.medium.level)
    }

    @Test func carolsAreWellFormed() {
        #expect(Carol.all.count >= 8)
        for carol in Carol.all {
            #expect(carol.bpm > 40 && carol.bpm < 200)
            #expect(!carol.upper.isEmpty)
            #expect(carol.totalBeats > 20)
            #expect((carol.upper + carol.lower).allSatisfy { (36...90).contains($0.pitch) && $0.beats > 0 && $0.start >= 0 })
        }
    }

    @Test func playerStaysSilentUntilAskedToPlay() {
        let player = MusicPlayer()
        #expect(!player.wantsToPlay)
        player.setPlaying(false)
        #expect(!player.wantsToPlay)
    }
}
