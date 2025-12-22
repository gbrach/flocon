import Testing
@testable import Flocon

struct ChristmasLightsTests {
    @Test func clearsNotchAndMenuBar() {
        for top: Float in [0, 24, 38] {
            let geometry = ChristmasLightGeometry(width: 1440, height: 900, topInset: top)
            #expect(geometry.wire.allSatisfy { $0.y < 900 - top && $0.x >= 0 && $0.x <= 1440 })
            #expect(geometry.bulbs.allSatisfy { $0.position.y + 6 < 900 - top })
            // hung edge to edge from the bar
            #expect(abs(geometry.wire.first!.x) < 0.001 && abs(geometry.wire.last!.x - 1440) < 0.001)
            #expect(abs(geometry.wire.first!.y - (900 - top - 2)) < 0.001)
        }
    }
    @Test func fitsSmallExternalDisplays() {
        let geometry = ChristmasLightGeometry(width: 320, height: 480, topInset: 24)
        #expect(geometry.bulbs.allSatisfy { $0.position.x > 0 && $0.position.x < 320 })
    }
    @Test func densityChangesTheBulbCount() {
        func count(_ density: LightDensity) -> Int {
            ChristmasLightGeometry(width: 1440, height: 900, topInset: 24, style: LightStyle(density: density)).bulbs.count
        }
        #expect(count(.sparse) < count(.normal) && count(.normal) < count(.dense))
        #expect(count(.normal) == ChristmasLightGeometry(width: 1440, height: 900, topInset: 24).bulbs.count)
    }
    @Test func warmWhiteUsesOneColorAndClassicUsesFour() {
        func colors(_ color: LightColor) -> Set<[Float]> {
            let bulbs = ChristmasLightGeometry(width: 1440, height: 900, topInset: 24, style: LightStyle(color: color)).bulbs
            return Set(bulbs.map { [$0.color.x, $0.color.y, $0.color.z] })
        }
        #expect(colors(.warmWhite).count == 1)
        #expect(colors(.classic).count == 4)
    }
    @Test func bulbsCarryTheirBlinkPatternAndPosition() {
        for blink in LightBlink.allCases {
            let bulbs = ChristmasLightGeometry(width: 1440, height: 900, topInset: 24, style: LightStyle(blink: blink)).bulbs
            #expect(bulbs.allSatisfy { $0.motion.x == Float(blink.rawValue) && $0.motion.z == 2 })
            #expect(bulbs.enumerated().allSatisfy { $0.element.motion.y == Float($0.offset) })
        }
    }
    @Test func unsetPreferencesKeepTheOriginalLook() {
        #expect(LightStyle.standard == LightStyle(density: .normal, color: .classic, blink: .steady))
    }
}
