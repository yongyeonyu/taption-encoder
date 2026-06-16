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

        contentScale = scale
        bannerScale = min(max(scale, 0.74), 1)
        verticalSpacing = max(5, 12 * scale)
        horizontalPadding = isPad ? max(28, 40 * widthScale) : max(12, 20 * widthScale)
        verticalPadding = max(6, 14 * scale)
        controlHeight = max(34, 44 * scale)
        filePanelHeight = min(max(isPad ? 260 : 170, canvasHeight * (isPad ? 0.34 : 0.28)), isPad ? 440 : 270)
        headerIconSize = max(18, 24 * scale)
        headerFont = scale < 0.84 ? .subheadline : .title3
        buttonFont = scale < 0.84 ? .caption.weight(.semibold) : .body
    }
}
