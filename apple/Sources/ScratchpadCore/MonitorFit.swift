import CoreGraphics

/// How a sheet sits on a monitor: the scale that fits its content, and the paper to draw at that
/// scale. A sheet has no stored size or shape, only blocks at points, so the paper can fill a wide
/// panel by reaching past the content, with nothing saved and the blocks where they always were.
public struct MonitorFit {
    public let scale: CGFloat
    /// At least `content`, in canvas points; more wherever the panel has room left.
    public let paper: CGSize

    public init(content: CGSize, space: CGSize, least: CGFloat, most: CGFloat) {
        let fit = min(space.width / content.width, space.height / content.height)
        scale = min(most, max(least, fit))
        paper = CGSize(width: max(content.width, space.width / scale),
                       height: max(content.height, space.height / scale))
    }
}
