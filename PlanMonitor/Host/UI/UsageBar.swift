import SwiftUI

/// The usage bar every provider draws.
///
/// Deliberately not `ProgressView().tint()`: a status-item popover is not the key window of
/// an accessory app, and AppKit desaturates accent-tinted controls in that state, so the
/// system bar rendered grey however it was tinted. Filling the shape directly keeps the
/// severity colour under every window state.
struct UsageBar: View {
    let fraction: Double
    let color: Color
    var height: CGFloat = 6

    private var clamped: Double {
        min(max(fraction, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                Capsule()
                    .fill(color)
                    // A non-zero value always shows a sliver, so "1% used" is not invisible.
                    .frame(width: clamped > 0 ? max(proxy.size.width * clamped, height) : 0)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}
