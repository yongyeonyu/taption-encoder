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
    TaptionFFmpegDecodeBridgeStatusNoFramesDecoded = -10,
    TaptionFFmpegDecodeBridgeStatusAudioStreamMissing = -11,
    TaptionFFmpegDecodeBridgeStatusAudioSampleFormatUnsupported = -12,
    TaptionFFmpegDecodeBridgeStatusNoAudioSamplesDecoded = -13
} TaptionFFmpegDecodeBridgeStatus;

typedef struct TaptionFFmpegDecodeBridgeProbeResult {
    int32_t width;
    int32_t height;
    int32_t frameCount;
    double durationSeconds;
    double averageFrameRate;
    int32_t sampleAspectRatioNumerator;
    int32_t sampleAspectRatioDenominator;
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

typedef struct TaptionFFmpegDecodeBridgeWritableNV12Frame {
    int32_t frameIndex;
    int32_t width;
    int32_t height;
    int32_t yBytesPerRow;
    int32_t uvBytesPerRow;
    double ptsSeconds;
    uint8_t *yBytes;
    uint8_t *uvBytes;
} TaptionFFmpegDecodeBridgeWritableNV12Frame;

typedef struct TaptionFFmpegDecodeBridgeAudioProbeResult {
    int32_t sampleRate;
    int32_t channelCount;
    int32_t sampleFormat;
    int32_t codecID;
    int64_t sampleCount;
    double durationSeconds;
    char codecName[64];
    char sampleFormatName[64];
} TaptionFFmpegDecodeBridgeAudioProbeResult;

typedef struct TaptionFFmpegDecodeBridgeAudioFrame {
    int32_t frameIndex;
    int32_t sampleRate;
    int32_t channelCount;
    int32_t sampleCount;
    double ptsSeconds;
    const int16_t *interleavedS16Samples;
} TaptionFFmpegDecodeBridgeAudioFrame;

typedef int32_t (*TaptionFFmpegDecodeBridgeFrameCallback)(
    const TaptionFFmpegDecodeBridgeFrame *frame,
    void *opaque
);

typedef int32_t (*TaptionFFmpegDecodeBridgeNV12FrameCallback)(
    TaptionFFmpegDecodeBridgeWritableNV12Frame *frame,
    void *opaque
);

typedef int32_t (*TaptionFFmpegDecodeBridgeAudioFrameCallback)(
    const TaptionFFmpegDecodeBridgeAudioFrame *frame,
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

int32_t taption_ffmpeg_decode_bridge_decode_video_to_nv12(
    const char *sourcePath,
    int32_t maximumFrameCount,
    TaptionFFmpegDecodeBridgeNV12FrameCallback acquireCallback,
    TaptionFFmpegDecodeBridgeNV12FrameCallback commitCallback,
    void *opaque,
    TaptionFFmpegDecodeBridgeProbeResult *result,
    char *errorBuffer,
    int32_t errorBufferCapacity
);

int32_t taption_ffmpeg_decode_bridge_probe_audio_s16(
    const char *sourcePath,
    TaptionFFmpegDecodeBridgeAudioProbeResult *result,
    char *errorBuffer,
    int32_t errorBufferCapacity
);

int32_t taption_ffmpeg_decode_bridge_decode_audio_s16(
    const char *sourcePath,
    TaptionFFmpegDecodeBridgeAudioFrameCallback callback,
    void *opaque,
    TaptionFFmpegDecodeBridgeAudioProbeResult *result,
    char *errorBuffer,
    int32_t errorBufferCapacity
);

#ifdef __cplusplus
}
#endif

#endif
