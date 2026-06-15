import SwiftUI

struct EncoderModePicker: View {
    @Binding var selectedMode: TaptionEncoderMode
    var isEnabled: Bool
    var recommendation: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Encoder", selection: $selectedMode) {
                Text("Hardware").tag(TaptionEncoderMode.hardware)
                Text("Software").tag(TaptionEncoderMode.software)
            }
            .pickerStyle(.segmented)
            .disabled(!isEnabled)

            Label(recommendation, systemImage: "cpu")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
