import Foundation

protocol EncoderServicing: TaptionVideoEncoding {}

struct FakeEncoderService: EncoderServicing {
    func encode(
        plan: TaptionEncodingPlan,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionEncodingResult {
        let totalSteps = 24
        progress(TaptionEncodingProgress(
            stage: .preparing,
            fractionCompleted: 0,
            elapsedTime: 0,
            estimatedRemainingTime: nil
        ))

        for step in 1...totalSteps {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 120_000_000)

            let fraction = Double(step) / Double(totalSteps)
            let elapsed = Double(step) * 0.12
            let remaining = max(0, Double(totalSteps - step) * 0.12)
            progress(TaptionEncodingProgress(
                stage: step == totalSteps ? .waitingForSaveGate : .encoding,
                fractionCompleted: fraction,
                elapsedTime: elapsed,
                estimatedRemainingTime: remaining,
                currentFrame: Int64(step * 30),
                totalFrames: Int64(totalSteps * 30)
            ))
        }

        guard let temporaryOutputURL = plan.temporaryOutputURL else {
            throw TaptionVideoCoreError.missingTemporaryOutputURL
        }

        return TaptionEncodingResult(
            planID: plan.id,
            temporaryOutputURL: temporaryOutputURL,
            finalOutputURL: nil,
            usedBackend: plan.encoderSelection.backend ?? .simulatedHardware,
            usedMode: plan.encoderSelection.requestedMode
        )
    }

    func cancelEncoding(planID: UUID) async {}
}
