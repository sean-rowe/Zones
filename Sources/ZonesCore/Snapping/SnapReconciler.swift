import CoreGraphics
import Foundation

/// Verdict of whether a window accepted a target snap rectangle.
public enum SnapVerdict: Equatable, Sendable {
    /// The window accepted the frame within quantisation slack on both axes.
    case accepted
    /// The window refused one or both axes beyond quantisation slack (e.g. minimum size constraints).
    case axisRefused(widthRefused: Bool, heightRefused: Bool, actual: CGRect, target: CGRect)

    public var isAccepted: Bool {
        self == .accepted
    }
}

/// Evaluates whether an actual window frame complies with a requested snap frame,
/// accounting for macOS character-cell quantization and minimum-size clamping.
///
/// NOTE: Never uses exact CGRect equality (`==`).
public enum SnapReconciler {
    /// Maximum deviation (in points) permitted on each axis to consider the snap successful.
    /// Covers character-cell stepping (Terminal) and minor platform insets.
    public static let quantisationSlack: CGFloat = 16.0

    /// Compares actual frame against target frame using slack tolerance on all edges.
    public static func reconcile(actual: CGRect, target: CGRect, slack: CGFloat = quantisationSlack) -> SnapVerdict {
        let widthDiff = abs(actual.width - target.width)
        let heightDiff = abs(actual.height - target.height)
        let xDiff = abs(actual.origin.x - target.origin.x)
        let yDiff = abs(actual.origin.y - target.origin.y)

        let widthRefused = widthDiff > slack
        let heightRefused = heightDiff > slack
        let posRefused = xDiff > slack || yDiff > slack

        if !widthRefused && !heightRefused && !posRefused {
            return .accepted
        } else {
            return .axisRefused(
                widthRefused: widthRefused,
                heightRefused: heightRefused,
                actual: actual,
                target: target
            )
        }
    }
}
