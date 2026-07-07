#ifndef TAPTION_FFMPEG_DECODE_BRIDGE_H
#define TAPTION_FFMPEG_DECODE_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum TaptionFFmpegDecodeBridgeStatus {
    TaptionFFmpegDecodeBridgeStatusOK = 0,
    TaptionFFmpegDecodeBridgeStatusInvalidArgument = -1,
    TaptionFFmpegDecodeBridgeStatusOpenInputFailed = -2,
    TaptionFFmpegDecodeBridgeStatusStreamInfoFailed = -3,
    TaptionFFmpegDecodeBridgeStatusVideoStreamMissing = -4,
    TaptionFFmpegDecodeBridgeStatusDecoderMissing = -5,
    TaptionFFmpegDecodeBridgeStatusDecoderOpenFailed = -6,
    TaptionFFmpegDecodeBridgeStatusDecodeFailed = -7,
    TaptionFFmpegDecodeBridgeStatusScaleFailed = -8,
    TaptionFFmpegDecodeBridgeStatusCallbackFailed = -9,
    TaptionFFmpegDecodeBridgeStatusNoFramesDecoded = -10
} TaptionFFmpegDecodeBridgeStatus;

typedef struct TaptionFFmpegDecodeBridgeProbeResult {
    int32_t width;
    int32_t height;
    int32_t frameCount;
    double durationSeconds;
    double averageFrameRate;
    int32_t codecID;
    int32_t pixelFormat;
    char codecName[64];
    char pixelFormatName[64];
} TaptionFFmpegDecodeBridgeProbeResult;

typedef struct TaptionFFmpegDecodeBridgeFrame {
    int32_t frameIndex;
    int32_t width;
    int32_t height;
    int32_t bytesPerRow;
    double ptsSeconds;
    const uint8_t *bgraBytes;
} TaptionFFmpegDecodeBridgeFrame;

typedef int32_t (*TaptionFFmpegDecodeBridgeFrameCallback)(
    const TaptionFFmpegDecodeBridgeFrame *frame,
    void *opaque
);

int32_t taption_ffmpeg_decode_bridge_probe_video(
    const char *sourcePath,
    TaptionFFmpegDecodeBridgeProbeResult *result,
    char *errorBuffer,
    int32_t errorBufferCapacity
);

int32_t taption_ffmpeg_decode_bridge_decode_video_to_bgra(
    const char *sourcePath,
    int32_t maximumFrameCount,
    TaptionFFmpegDecodeBridgeFrameCallback callback,
    void *opaque,
    TaptionFFmpegDecodeBridgeProbeResult *result,
    char *errorBuffer,
    int32_t errorBufferCapacity
);

#ifdef __cplusplus
}
#endif

#endif
