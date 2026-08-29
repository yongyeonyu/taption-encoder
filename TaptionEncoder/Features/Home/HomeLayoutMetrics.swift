import SwiftUI
import UIKit

struct HomeLayoutMetrics {
    var canvasWidth: CGFloat
    var canvasHeight: CGFloat
    var usesPadLandscapeColumns: Bool
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
        let isPad = userInterfaceIdiom == .pad
        let availableWidth = max(1, size.width)
        let availableHeight = max(1, size.height)
        let portraitWidth = min(size.width, size.height)
        usesPadLandscapeColumns = isPad && availableWidth > availableHeight

        if usesPadLandscapeColumns {
            canvasWidth = min(availableWidth, 1_180)
            canvasHeight = availableHeight
        } else if isPad {
            let idealAspect: CGFloat = 834 / 1194
            let portraitCanvasWidth = min(availableWidth, availableHeight * idealAspect)
            canvasWidth = min(max(portraitCanvasWidth, 600), 820)
            canvasHeight = availableHeight
        } else {
            canvasWidth = min(max(size.width, 320), 430)
            canvasHeight = availableHeight
        }

        let referenceWidth: CGFloat = usesPadLandscapeColumns ? 1194 : (isPad ? 834 : 390)
        let referenceHeight: CGFloat = usesPadLandscapeColumns ? 834 : (isPad ? 1194 : 844)
        let minimumScale: CGFloat = isPad ? 0.82 : 0.72
        let maximumScale: CGFloat = isPad ? 1.18 : 1
        let heightScale = min(max(availableHeight / referenceHeight, minimumScale), maximumScale)
        let scaleWidth = usesPadLandscapeColumns ? availableWidth : portraitWidth
        let widthScale = min(max(scaleWidth / referenceWidth, isPad ? 0.82 : 0.84), maximumScale)
        let scale = min(heightScale, widthScale)

        let compactHeightPressure = availableHeight < (usesPadLandscapeColumns ? 700 : (isPad ? 900 : 760))
        contentScale = compactHeightPressure ? max(minimumScale, scale * 0.92) : scale
        bannerScale = min(max(contentScale, isPad ? 0.74 : 0.68), 1)
        verticalSpacing = compactHeightPressure ? max(4, 7 * contentScale) : max(5, 9 * contentScale)
        horizontalPadding = isPad ? max(28, 40 * widthScale) : max(12, 20 * widthScale)
        verticalPadding = compactHeightPressure ? max(4, 8 * contentScale) : max(5, 10 * contentScale)
        controlHeight = max(32, 42 * contentScale)
        footerExitButtonHeight = max(32, 40 * contentScale)
        headerIconSize = max(17, 23 * contentScale)
        headerFont = contentScale < 0.84 ? .subheadline : .title3
        buttonFont = contentScale < 0.84 ? .caption.weight(.semibold) : .body
        columnSpacing = usesPadLandscapeColumns ? max(18, 24 * widthScale) : 0
        columnWidth = usesPadLandscapeColumns
            ? max(1, (canvasWidth - (horizontalPadding * 2) - columnSpacing) / 2)
            : max(1, canvasWidth - (horizontalPadding * 2))

        let bannerHeight = 50 * bannerScale
        let headerHeight = 34 * contentScale
        let sourceActionHeight = (controlHeight * 2) + 10
        let outputSelectorHeight = max(controlHeight, 52 * contentScale)
        let codecSummaryHeight = max(66, 78 * contentScale)
        footerAdSeparationHeight = max(8, 12 * contentScale)
        let progressCardHeight = reservesFailureLogArea
            ? max(150, 188 * contentScale)
            : max(92, 116 * contentScale)
        let visibleSpacingCount: CGFloat = reservesFailureLogArea ? 8 : 9
        if usesPadLandscapeColumns {
            let sharedHeight = (bannerHeight * 2)
                + headerHeight
                + footerAdSeparationHeight
                + (verticalSpacing * 3)
                + (verticalPadding * 2)
            let columnContentHeight = max(0, canvasHeight - sharedHeight)
            filePanelHeight = max(120, columnContentHeight)
        } else {
            let fixedComponentHeight = (bannerHeight * 2)
                + headerHeight
                + sourceActionHeight
                + outputSelectorHeight
                + codecSummaryHeight
                + progressCardHeight
                + footerExitButtonHeight
                + footerAdSeparationHeight
                + (verticalSpacing * visibleSpacingCount)
                + (verticalPadding * 2)
            let remainingHeight = canvasHeight - fixedComponentHeight
            filePanelHeight = max(0, remainingHeight)
        }
    }
}
