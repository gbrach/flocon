import AppKit

enum Preferences {
    private static let defaults = UserDefaults.standard

    static func registerDefaults() {
        defaults.register(defaults: [
            "enabled": true, "snowfall": Snowfall.moderate.rawValue,
            "accumulate": true, "meltSnow": true, "snowOnWindows": true,
            "interactions": true, "wind": 1.0, "energySaver": false,
            "christmasLights": false, "lightDensity": LightDensity.normal.rawValue,
            "lightColor": LightColor.classic.rawValue, "lightBlink": LightBlink.steady.rawValue, "behindWindows": false, "showInScreenshots": false,
        ])
    }
    static var christmasLights: Bool {
        get { defaults.bool(forKey: "christmasLights") }
        set { defaults.set(newValue, forKey: "christmasLights") }
    }
    static var lightStyle: LightStyle {
        LightStyle(density: LightDensity(rawValue: defaults.integer(forKey: "lightDensity")) ?? .normal,
                   color: LightColor(rawValue: defaults.integer(forKey: "lightColor")) ?? .classic,
                   blink: LightBlink(rawValue: defaults.integer(forKey: "lightBlink")) ?? .steady)
    }
    static var enabled: Bool {
        get { defaults.bool(forKey: "enabled") }
        set { defaults.set(newValue, forKey: "enabled") }
    }
    static var snowfall: Snowfall {
        get { Snowfall(rawValue: defaults.integer(forKey: "snowfall")) ?? .moderate }
        set { defaults.set(newValue.rawValue, forKey: "snowfall") }
    }
    static var wind: Float {
        get { min(3, max(0, defaults.float(forKey: "wind"))) }
        set { defaults.set(newValue, forKey: "wind") }
    }
    static var accumulate: Bool {
        get { defaults.bool(forKey: "accumulate") }
        set { defaults.set(newValue, forKey: "accumulate") }
    }
    static var meltSnow: Bool {
        get { defaults.bool(forKey: "meltSnow") }
        set { defaults.set(newValue, forKey: "meltSnow") }
    }
    static var snowOnWindows: Bool {
        get { defaults.bool(forKey: "snowOnWindows") }
        set { defaults.set(newValue, forKey: "snowOnWindows") }
    }
    static var interactions: Bool {
        get { defaults.bool(forKey: "interactions") }
        set { defaults.set(newValue, forKey: "interactions") }
    }
    static var energySaver: Bool {
        get { defaults.bool(forKey: "energySaver") }
        set { defaults.set(newValue, forKey: "energySaver") }
    }
    static var behindWindows: Bool {
        get { defaults.bool(forKey: "behindWindows") }
        set { defaults.set(newValue, forKey: "behindWindows") }
    }
    static var showInScreenshots: Bool {
        get { defaults.bool(forKey: "showInScreenshots") }
        set { defaults.set(newValue, forKey: "showInScreenshots") }
    }
}
