import CoreGraphics

/// A platform-independent snapshot in display-local points, with a bottom-left origin.
struct WindowSurface: Equatable {
    let id: CGWindowID
    let frame: CGRect
    let blockers: [CGRect]
    let cornerRadius: CGFloat
    let cornerExponent: CGFloat
    let isDock: Bool
}
