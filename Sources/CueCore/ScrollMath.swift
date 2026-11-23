public enum ScrollMath {
    /// Scroll offset that puts a line at the reading line (a fraction of the viewport from the top),
    /// clamped so the view never scrolls past either end of the content.
    public static func targetOffset(lineMinY: Double, viewportHeight: Double, contentHeight: Double,
                                    readingLine: Double = 0.3) -> Double {
        let maxOffset = max(0, contentHeight - viewportHeight)
        return min(max(0, lineMinY - readingLine * viewportHeight), maxOffset)
    }
}
