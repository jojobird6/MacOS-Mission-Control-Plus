import CoreGraphics

public enum CoverGeometry {
    /// How far a Mission Control thumbnail's shadow reaches past its frame. It falls downward, so it reaches
    /// further below the thumbnail than above it.
    public static let shadowSide: CGFloat = 16
    public static let shadowAbove: CGFloat = 12
    public static let shadowBelow: CGFloat = 20
    /// Space kept clear around neighboring thumbnails so their hover highlight isn't covered.
    public static let neighborClearance: CGFloat = 4
    /// Slack around thumbnails and Dock icons before the pointer counts as having left them.
    public static let activeAreaMargin: CGFloat = 24

    /// The area a cover must paint to hide a thumbnail and its shadow, in Cocoa coordinates (y up).
    public static func coverRect(for thumbnail: CGRect) -> CGRect {
        CGRect(x: thumbnail.minX - shadowSide, y: thumbnail.minY - shadowBelow,
               width: thumbnail.width + 2 * shadowSide, height: thumbnail.height + shadowBelow + shadowAbove)
    }

    /// Parts of `cover` that must stay transparent because other, still-visible thumbnails are there.
    /// Rects are in the same coordinate space as the inputs.
    public static func holes(in cover: CGRect, neighbors: [CGRect]) -> [CGRect] {
        neighbors.compactMap { neighbor in
            let hole = neighbor.insetBy(dx: -neighborClearance, dy: -neighborClearance).intersection(cover)
            return hole.isNull || hole.isEmpty ? nil : hole
        }
    }

    /// The region where the user is still working: around all thumbnails and Dock icons.
    public static func activeArea(thumbnails: [CGRect], dockItems: [CGRect]) -> CGRect {
        let union = (thumbnails + dockItems).reduce(CGRect.null) { $0.union($1) }
        return union.isNull ? .null : union.insetBy(dx: -activeAreaMargin, dy: -activeAreaMargin)
    }
}
