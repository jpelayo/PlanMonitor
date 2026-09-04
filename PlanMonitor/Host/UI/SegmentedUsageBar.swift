import SwiftUI

/// A `UsageBar` with evenly spaced segment hints, so a multi-day window can be read against a
/// daily pace: seven segments on a 7-day limit make "am I a day ahead or behind" estimable at a
/// glance. The segments divide the **quota**, not the calendar — they are a scale, not a date.
///
/// Composed over `UsageBar` rather than forked from it, so the track, the severity fill and the
/// minimum-sliver rule stay in one place.
///
/// The notches are plain dark lines drawn on top. Do **not** reach for `.compositingGroup()` plus
/// `.blendMode(.destinationOut)` to punch them out instead: flattening the bar into an offscreen
/// layer drops the vibrancy blend on the track's `.quaternary` fill, which then renders against
/// transparent black and turns the unfilled half solid black inside a popover — visibly different
/// from every plain `UsageBar` beside it. Same family of trap as the tinted-`ProgressView` note in
/// `UsageBar`: system materials only look right when the view is composited normally.
struct SegmentedUsageBar: View {
    let fraction: Double
    let color: Color
    var segments: Int = 7
    var height: CGFloat = 6
    var notchWidth: CGFloat = 1
    /// Strength of the notch lines. Raise for a harder rule, lower for a hint.
    var notchOpacity: Double = 0.55

    var body: some View {
        UsageBar(fraction: fraction, color: color, height: height)
            .overlay { notches }
            .accessibilityHidden(true)
    }

    private var notches: some View {
        GeometryReader { proxy in
            let count = max(segments, 1)
            ZStack(alignment: .leading) {
                ForEach(Array(1..<count), id: \.self) { index in
                    Rectangle()
                        .frame(width: notchWidth)
                        .offset(x: proxy.size.width * CGFloat(index) / CGFloat(count) - notchWidth / 2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .foregroundStyle(Color.black.opacity(notchOpacity))
        }
    }
}
