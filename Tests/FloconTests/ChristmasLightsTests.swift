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
}
