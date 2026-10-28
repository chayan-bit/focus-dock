import CoreGraphics

/// Every visual constant of the dock.
/// Sources: docs/research/rea-dock.md (static teardown) and docs/research/phase0.md (live
/// measurements at tilesize 75, dark appearance). Ratios are of the tile size; Phase 0 measured
/// one tile size, so scaling with tile size is an assumption shared by all ratios below.
public enum DockMetrics {
    // MARK: Tile size (rea-dock H: Dock asm@0x1000085d4)

    public static let defaultTileSize: CGFloat = 64
    public static let smallDisplayTileSize: CGFloat = 52
    public static let smallDisplayMaxHeight: CGFloat = 800
    /// The Dock accepts `0 < tilesize < 257`; anything else falls back to the default.
    public static let tileSizeExclusiveMax: Double = 257

    public static func tileSize(preference: Double?, mainDisplayHeight: CGFloat) -> CGFloat {
        if let preference, preference > 0, preference < tileSizeExclusiveMax {
            return CGFloat(preference)
        }
        return mainDisplayHeight <= smallDisplayMaxHeight ? smallDisplayTileSize : defaultTileSize
    }

    // MARK: Cells and platter (phase0 section 1, H)

    /// A tile's cell is the icon plus 4 pt (at 75), icon centred; cells abut, so this is the pitch.
    public static let cellExtraRatio: CGFloat = 4.0 / 75
    /// Platter edge to the first/last cell edge.
    public static let platterHorizontalInsetRatio: CGFloat = 8.75 / 75
    /// Platter edge to the icon top/bottom (10 pt at 75).
    public static let platterVerticalInsetRatio: CGFloat = 10.0 / 75
    /// 30 pt at 75 (phase0: M-H).
    public static let platterCornerRadiusRatio: CGFloat = 0.40
    public static let screenBottomMargin: CGFloat = 5

    public static func cellWidth(tileSize: CGFloat) -> CGFloat { tileSize * (1 + cellExtraRatio) }
    public static func platterHorizontalInset(tileSize: CGFloat) -> CGFloat { tileSize * platterHorizontalInsetRatio }
    public static func platterVerticalInset(tileSize: CGFloat) -> CGFloat { tileSize * platterVerticalInsetRatio }
    public static func platterCornerRadius(tileSize: CGFloat) -> CGFloat { tileSize * platterCornerRadiusRatio }

    /// Specular rim on the top and bottom edges (phase0: M width).
    public static let platterRimWidth: CGFloat = 1
    // shortcut: phase0 confidence L for the rim alpha (one dark wallpaper); re-measure over a light one.
    public static let platterRimOpacity: Double = 0.30

    // Only drawn by the Reduce Transparency fallback; Liquid Glass renders its own shadow and rim.
    // shortcut: phase0 confidence L (dark wallpaper hides it), re-measure over a light wallpaper.
    public static let shadowRadius: CGFloat = 3
    // shortcut: phase0 confidence L, re-measure over a light wallpaper.
    public static let shadowOpacity: Double = 0.4
    // shortcut: phase0 confidence L, re-measure over a light wallpaper.
    public static let shadowYOffset: CGFloat = 1

    // MARK: Running indicator (rea-dock H: DOCKIndicatorLayer; phase0 section 2)

    public struct Indicator: Equatable, Sendable {
        public let diameter: CGFloat
        public let cornerRadius: CGFloat
    }

    public static let smallIndicatorTileThreshold: CGFloat = 33

    public static func indicator(forTileSize tileSize: CGFloat) -> Indicator {
        tileSize < smallIndicatorTileThreshold
            ? Indicator(diameter: 3, cornerRadius: 1.5)
            : Indicator(diameter: 4, cornerRadius: 2)
    }

    /// Dot centre below the icon bottom (4 pt at 75).
    public static let indicatorCentreBelowTileRatio: CGFloat = 4.0 / 75
    // shortcut: phase0 confidence L (one dark wallpaper, dark appearance only); light appearance unmeasured.
    public static let indicatorOpacity: Double = 0.6

    // MARK: Divider (phase0 section 3, H geometry, M alpha)

    /// Horizontal slot the divider takes between two cells. phase0 AX frames say 35 pt at 75, but
    /// on-screen dot pitch across the divider is 79 + 36 pt (docs/research/e2e-phase1.md).
    public static let dividerSlotRatio: CGFloat = 36.0 / 75
    public static let dividerThickness: CGFloat = 1
    /// The line sits 1 pt right of the slot centre at 75 (e2e-phase1 pixel measurement).
    public static let dividerLineOffsetRatio: CGFloat = 1.0 / 75
    /// Line height, centred on the icon (71 pt at 75).
    public static let dividerHeightRatio: CGFloat = 71.0 / 75
    // shortcut: measured in dark appearance only; light appearance unmeasured.
    public static let dividerOpacity: Double = 0.29

    public static func dividerSlot(tileSize: CGFloat) -> CGFloat { tileSize * dividerSlotRatio }

    // MARK: Hover label ("cartouche", phase0 section 4)

    public static let cartoucheBodyHeight: CGFloat = 23
    public static let cartoucheCornerRadius: CGFloat = 11.5
    public static let cartoucheHorizontalPadding: CGFloat = 13.5
    /// Regular weight (phase0: M-L, medium not excluded).
    public static let cartoucheFontSize: CGFloat = 14
    /// Body bottom above the platter top.
    public static let cartoucheGapAbovePlatter: CGFloat = 10.75
    // shortcut: phase0 confidence L for the tail size, re-measure from a 3x zoom crop.
    public static let cartoucheTailHeight: CGFloat = 7.5
    // shortcut: phase0 confidence L for the tail size, re-measure from a 3x zoom crop.
    public static let cartoucheTailBaseWidth: CGFloat = 10
    /// Reduce Transparency fill, dark appearance; light appearance unmeasured.
    public static let cartoucheFallbackDarkRGB: (red: Double, green: Double, blue: Double) = (34 / 255, 34 / 255, 36 / 255)
    /// Room reserved around the platter so labels of edge tiles are not clipped.
    public static let cartoucheMaxHalfWidth: CGFloat = 140

    // MARK: Mode pills (Phase 2)

    // shortcut: pill geometry is read off the demo video frames, not measured; re-measure in E2E.
    /// Collapsed pill diameter and expanded pill height (44 pt at 75).
    public static let pillHeightRatio: CGFloat = 44.0 / 75
    /// Gap between neighbouring pills and between the countdown pill and Stay.
    public static let pillSpacingRatio: CGFloat = 6.0 / 75
    public static let pillSymbolSizeRatio: CGFloat = 18.0 / 75
    /// Width reserved for the symbol in an expanded pill, so labels line up.
    public static let pillSymbolBoxRatio: CGFloat = 22.0 / 75
    public static let pillFontSizeRatio: CGFloat = 15.0 / 75
    public static let pillHorizontalPaddingRatio: CGFloat = 13.0 / 75
    public static let pillSymbolLabelGapRatio: CGFloat = 6.0 / 75
    /// Fill of a collapsed pill over the platter glass.
    public static let pillCollapsedFillOpacity: Double = 0.12
    /// Fill of a collapsed pill in the theme's accent, while a theme is applied.
    public static let themedPillFillOpacity: Double = 0.3

    public static func pillHeight(tileSize: CGFloat) -> CGFloat { (tileSize * pillHeightRatio).rounded() }
    public static func pillSpacing(tileSize: CGFloat) -> CGFloat { tileSize * pillSpacingRatio }
    public static func pillFontSize(tileSize: CGFloat) -> CGFloat { (tileSize * pillFontSizeRatio).rounded() }
    public static func pillSymbolSize(tileSize: CGFloat) -> CGFloat { (tileSize * pillSymbolSizeRatio).rounded() }

    /// Symbol + gap + label, padded; `labelWidth` is the measured text width.
    public static func expandedPillWidth(labelWidth: CGFloat, tileSize: CGFloat) -> CGFloat {
        let fixed = 2 * pillHorizontalPaddingRatio + pillSymbolBoxRatio + pillSymbolLabelGapRatio
        return (tileSize * fixed + labelWidth).rounded(.up)
    }

    /// The white "Stay" capsule: label only, padded.
    public static func stayWidth(labelWidth: CGFloat, tileSize: CGFloat) -> CGFloat {
        (2 * tileSize * pillHorizontalPaddingRatio + labelWidth).rounded(.up)
    }

    // MARK: Launch bounce (phase0 section 6)

    /// Apex above rest (20 pt at 75).
    public static let bounceApexRatio: CGFloat = 20.0 / 75
    public static let bounceHoldSeconds: Double = 0.10
    public static let bounceFallSeconds: Double = 0.30
    // shortcut: the rise and the repeat period were never observed (Calculator launched too fast); rise assumed to mirror the fall.
    public static let bounceRiseSeconds: Double = 0.30
    public static var bouncePeriod: Double { bounceRiseSeconds + bounceHoldSeconds + bounceFallSeconds }

    /// Height above rest, in points, `elapsed` seconds into a launch. Rise decelerates,
    /// the fall accelerates like gravity (phase0), and the cycle repeats until launch ends.
    public static func bounceOffset(elapsed: Double, tileSize: CGFloat) -> CGFloat {
        let apex = tileSize * bounceApexRatio
        let t = max(elapsed, 0).truncatingRemainder(dividingBy: bouncePeriod)
        if t < bounceRiseSeconds {
            let p = t / bounceRiseSeconds
            return apex * CGFloat(1 - (1 - p) * (1 - p))
        }
        if t < bounceRiseSeconds + bounceHoldSeconds { return apex }
        let p = (t - bounceRiseSeconds - bounceHoldSeconds) / bounceFallSeconds
        return apex * CGFloat(1 - p * p)
    }

    /// Seconds until the bounce in progress `elapsed` seconds into a launch is back at rest.
    public static func bounceTimeToRest(elapsed: Double) -> Double {
        let t = max(elapsed, 0).truncatingRemainder(dividingBy: bouncePeriod)
        return t == 0 ? 0 : bouncePeriod - t
    }

    /// Transparent space above the platter for the cartouche and the bounce.
    public static func headroom(tileSize: CGFloat) -> CGFloat {
        let label = cartoucheGapAbovePlatter + cartoucheBodyHeight
        return max(label, tileSize * bounceApexRatio) + 8
    }
}
