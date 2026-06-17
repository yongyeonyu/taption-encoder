import SwiftUI
import UIKit

struct HomeLayoutMetrics {
    var canvasWidth: CGFloat
    var canvasHeight: CGFloat
    var contentScale: CGFloat
    var bannerScale: CGFloat
    var verticalSpacing: CGFloat
    var horizontalPadding: CGFloat
    var verticalPadding: CGFloat
    var controlHeight: CGFloat
    var filePanelHeight: CGFloat
    var headerIconSize: CGFloat
    var headerFont: Font
    var buttonFont: Font

    init(size: CGSize) {
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        let portraitWidth = min(size.width, size.height)
        let portraitHeight = max(size.width, size.height)

        if isPad {
            let idealAspect: CGFloat = 834 / 1194
            let availableWidth = max(320, size.width)
            let availableHeight = max(568, size.height)
            let portraitCanvasWidth = min(availableWidth, availableHeight * idealAspect)
            canvasWidth = min(max(portraitCanvasWidth, 600), 820)
            canvasHeight = availableHeight
        } else {
            canvasWidth = min(max(size.width, 320), 430)
            canvasHeight = size.height
        }

        let referenceWidth: CGFloat = isPad ? 834 : 390
        let referenceHeight: CGFloat = isPad ? 1194 : 844
        let minimumScale: CGFloat = isPad ? 0.82 : 0.72
        let maximumScale: CGFloat = isPad ? 1.18 : 1
        let heightScale = min(max(portraitHeight / referenceHeight, minimumScale), maximumScale)
        let widthScale = min(max(portraitWidth / referenceWidth, isPad ? 0.82 : 0.84), maximumScale)
        let scale = min(heightScale, widthScale)

        let compactHeightPressure = portraitHeight < (isPad ? 900 : 760)
        contentScale = compactHeightPressure ? max(minimumScale, scale * 0.92) : scale
        bannerScale = min(max(contentScale, isPad ? 0.74 : 0.68), 1)
        verticalSpacing = compactHeightPressure ? max(4, 7 * contentScale) : max(5, 9 * contentScale)
        horizontalPadding = isPad ? max(28, 40 * widthScale) : max(12, 20 * widthScale)
        verticalPadding = compactHeightPressure ? max(4, 8 * contentScale) : max(5, 10 * contentScale)
        controlHeight = max(32, 42 * contentScale)
        headerIconSize = max(17, 23 * contentScale)
        headerFont = contentScale < 0.84 ? .subheadline : .title3
        buttonFont = contentScale < 0.84 ? .caption.weight(.semibold) : .body

        let bannerHeight = 50 * bannerScale
        let headerHeight = 34 * contentScale
        let sourceActionHeight = (controlHeight * 2) + 10
        let outputSelectorHeight = max(controlHeight, 52 * contentScale)
        let codecSummaryHeight = max(66, 78 * contentScale)
        let progressCardHeight = max(92, 116 * contentScale)
        let fixedComponentHeight = (bannerHeight * 2)
            + headerHeight
            + sourceActionHeight
            + outputSelectorHeight
            + codecSummaryHeight
            + progressCardHeight
            + (verticalSpacing * 7)
            + (verticalPadding * 2)
        let remainingHeight = canvasHeight - fixedComponentHeight
        let minimumFilePanelHeight = isPad ? 170 * contentScale : 108 * contentScale
        let maximumFilePanelHeight = isPad ? 360 * contentScale : 205 * contentScale
        filePanelHeight = min(
            max(remainingHeight, minimumFilePanelHeight),
            maximumFilePanelHeight
        )
    }
}
