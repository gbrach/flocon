import Foundation

enum Snowfall: Int, CaseIterable {
    case off, light, moderate, heavy, variable

    var title: String {
        switch self {
        case .off: "Off"
        case .light: "Light"
        case .moderate: "Moderate"
        case .heavy: "Heavy"
        case .variable: "Variable"
        }
    }

    var flakesPerMegapoint: Float {
        switch self {
        case .off: 0
        case .light: 150
        case .moderate, .variable: 380
        case .heavy: 800
        }
    }
}
