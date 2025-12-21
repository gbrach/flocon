import Testing
@testable import Flocon

struct UpdateCheckerTests {
    @Test func readsTheVersionFromAReleaseTitle() {
        #expect(UpdateChecker.version(in: "Flocon 1.2.3") == [1, 2, 3])
        #expect(UpdateChecker.version(in: "v2.0") == [2, 0])
        #expect(UpdateChecker.version(in: "latest") == nil)
    }

    @Test func comparesVersionsNumerically() {
        #expect(UpdateChecker.isNewer([1, 10], than: [1, 9]))
        #expect(UpdateChecker.isNewer([1, 0, 1], than: [1, 0]))
        #expect(!UpdateChecker.isNewer([1, 0], than: [1, 0, 0]))
        #expect(!UpdateChecker.isNewer([1, 0, 0], than: [1, 1, 0]))
    }
}
