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
    /// Where the fill *would* be if the quota were spent evenly across the window, 0...1. Drawn as
    /// a pace reference: fill past the marker means the quota is going faster than the window is.
    /// `nil` draws no marker.
    var marker: Double?
    /// White, not red: red competes with the severity fill, which turns red at 90% used. White
    /// reads as a reference point rather than a warning, and holds contrast against the green,
    /// orange and red fills alike.
    var markerColor: Color = .white
    var markerWidth: CGFloat = 2
    /// Height of the marker. Defaults to the bar's own height, so it reads as a division of the
    /// bar rather than a tick floating in it. Larger values make it stand proud of the bar.
    var markerHeight: CGFloat?

    var body: some View {
        UsageBar(fraction: fraction, color: color, height: height)
            .overlay { notches }
            .overlay { paceMarker }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var paceMarker: some View {
        if let marker {
            GeometryReader { proxy in
                Capsule()
                    .fill(markerColor)
                    .frame(width: markerWidth, height: markerHeight ?? height)
                    .position(
                        x: proxy.size.width * min(max(marker, 0), 1),
                        y: height / 2
                    )
            }
        }
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
