import SwiftUI

struct PrimaryActionButton: View {
    var title: String
    var systemImage: String
    var isProminent: Bool
    var isEnabled: Bool
    var action: () -> Void

    var body: some View {
        if isProminent {
            button
                .buttonStyle(.borderedProminent)
        } else {
            button
                .buttonStyle(.bordered)
        }
    }

    private var button: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
        }
        .disabled(!isEnabled)
    }
}
