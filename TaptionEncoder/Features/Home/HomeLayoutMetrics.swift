import SwiftUI
import UIKit

struct HomeLayoutMetrics {
    /// Short side, in points, at which the layout switches to the wide (iPad) arrangement.
    ///
    /// The idiom cannot answer this. A foldable iPhone keeps `UIUserInterfaceIdiom.phone` in both
    /// poses, so the layout class has to come from the geometry:
    ///
    /// | Device | Points | Short side | Layout |
    /// | --- | --- | --- | --- |
    /// | iPhone Duo, folded (outer) | 466 × 678 | 466 | compact — the phone UI, scaled |
    /// | iPhone 18 Pro Max | 440 × 956 | 440 | compact |
    /// | iPhone Duo, unfolded (inner) | 626 × 890 | 626 | **wide** — the iPad UI |
    /// | iPad mini | 744 × 1133 | 744 | wide |
    ///
    /// 600 sits in the gap between 466 and 626, so no iPhone — landscape included, where the short
    /// side tops out at 440 — can reach it, and an unfolded Duo cannot miss it. Keying on the short
    /// side means the app never has to know a product name, and a future foldable with a different
    /// panel is handled by the same rule.
    static let wideLayoutMinimumShortSide: CGFloat = 600

    /// Whether this geometry gets the wide (iPad) arrangement.
    ///
    /// Shared with the orientation policy so the two cannot drift: a screen that is laid out like an
    /// iPad should also rotate like one.
    static func usesWideLayout(size: CGSize, userInterfaceIdiom: UIUserInterfaceIdiom) -> Bool {
        userInterfaceIdiom == .pad || min(size.width, size.height) >= wideLayoutMinimumShortSide
    }

    var canvasWidth: CGFloat
    var canvasHeight: CGFloat
    /// True when the screen is laid out with the iPad arrangement — a real iPad, or a foldable
    /// that is currently unfolded.
    var usesWideLayout: Bool
    var usesPadLandscapeColumns: Bool
    var usesScrollableLayout: Bool
    var columnSpacing: CGFloat
    var columnWidth: CGFloat
    var contentScale: CGFloat
    var bannerScale: CGFloat
    var verticalSpacing: CGFloat
    var horizontalPadding: CGFloat
    var verticalPadding: CGFloat
    var controlHeight: CGFloat
    var filePanelHeight: CGFloat
    var footerAdSeparationHeight: CGFloat
    var footerExitButtonHeight: CGFloat
    var headerIconSize: CGFloat
    var headerFont: Font
    var buttonFont: Font

    init(
        size: CGSize,
        reservesFailureLogArea: Bool = false
    ) {
        self.init(
            size: size,
            reservesFailureLogArea: reservesFailureLogArea,
            userInterfaceIdiom: UIDevice.current.userInterfaceIdiom
        )
    }

    init(
        size: CGSize,
        reservesFailureLogArea: Bool,
        userInterfaceIdiom: UIUserInterfaceIdiom
    ) {
        let usesWideLayout = Self.usesWideLayout(size: size, userInterfaceIdiom: userInterfaceIdiom)
        self.usesWideLayout = usesWideLayout
        let availableWidth = max(1, size.width)
        let availableHeight = max(1, size.height)
        let portraitWidth = min(size.width, size.height)
        usesPadLandscapeColumns = usesWideLayout && availableWidth > availableHeight
        usesScrollableLayout = !usesWideLayout && availableHeight < 500

        if usesPadLandscapeColumns {
            canvasWidth = min(availableWidth, 1_180)
            canvasHeight = availableHeight
        } else if usesWideLayout {
            let idealAspect: CGFloat = 834 / 1194
            let portraitCanvasWidth = min(availableWidth, availableHeight * idealAspect)
            canvasWidth = min(max(portraitCanvasWidth, 600), 820)
            canvasHeight = availableHeight
        } else {
            canvasWidth = min(max(size.width, 320), 430)
            canvasHeight = availableHeight
        }

        let referenceWidth: CGFloat = usesPadLandscapeColumns ? 1194 : (usesWideLayout ? 834 : 390)
        let referenceHeight: CGFloat = usesPadLandscapeColumns ? 834 : (usesWideLayout ? 1194 : 844)
        let minimumScale: CGFloat = usesWideLayout ? 0.82 : 0.72
        let maximumScale: CGFloat = usesWideLayout ? 1.18 : 1
        let heightScale = min(max(availableHeight / referenceHeight, minimumScale), maximumScale)
        let scaleWidth = usesPadLandscapeColumns ? availableWidth : portraitWidth
        let widthScale = min(max(scaleWidth / referenceWidth, usesWideLayout ? 0.82 : 0.84), maximumScale)
        let scale = min(heightScale, widthScale)

        let compactHeightPressure = availableHeight < (usesPadLandscapeColumns ? 700 : (usesWideLayout ? 900 : 760))
        contentScale = compactHeightPressure ? max(minimumScale, scale * 0.92) : scale
        bannerScale = min(max(contentScale, usesWideLayout ? 0.74 : 0.68), 1)
        verticalSpacing = compactHeightPressure ? max(4, 7 * contentScale) : max(5, 9 * contentScale)
        horizontalPadding = usesWideLayout ? max(28, 40 * widthScale) : max(12, 20 * widthScale)
        verticalPadding = compactHeightPressure ? max(4, 8 * contentScale) : max(5, 10 * contentScale)
        controlHeight = max(44, 42 * contentScale)
        footerExitButtonHeight = max(32, 40 * contentScale)
        headerIconSize = max(17, 23 * contentScale)
        headerFont = contentScale < 0.84 ? .subheadline : .title3
        buttonFont = contentScale < 0.84 ? .caption.weight(.semibold) : .body
        columnSpacing = usesPadLandscapeColumns ? max(18, 24 * widthScale) : 0
        columnWidth = usesPadLandscapeColumns
            ? max(1, (canvasWidth - (horizontalPadding * 2) - columnSpacing) / 2)
            : max(1, canvasWidth - (horizontalPadding * 2))

        let bannerHeight = 50 * bannerScale
        let headerHeight = max(44, 34 * contentScale)
        let sourceActionHeight = controlHeight
        let queueHeadingHeight: CGFloat = 48
        let outputSelectorHeight = max(74, 82 * contentScale)
        footerAdSeparationHeight = max(8, 12 * contentScale)
        let progressCardHeight = reservesFailureLogArea
            ? max(150, 188 * contentScale)
            : max(50, 58 * contentScale)
        let visibleSpacingCount: CGFloat = 8
        if usesPadLandscapeColumns {
            let sharedHeight = (bannerHeight * 2)
                + headerHeight
                + sourceActionHeight
                + footerAdSeparationHeight
                + (verticalSpacing * 3)
                + (verticalPadding * 2)
            let columnContentHeight = max(0, canvasHeight - sharedHeight)
            filePanelHeight = max(120, columnContentHeight)
        } else {
            let fixedComponentHeight = (bannerHeight * 2)
                + headerHeight
                + sourceActionHeight
                + queueHeadingHeight
                + outputSelectorHeight
                + progressCardHeight
                + footerAdSeparationHeight
                + (verticalSpacing * visibleSpacingCount)
                + (verticalPadding * 2)
            let remainingHeight = canvasHeight - fixedComponentHeight
            filePanelHeight = max(usesScrollableLayout ? 180 : 80, remainingHeight)
        }
    }
}
