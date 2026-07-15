#include "TaptionFFmpegDecodeBridge.h"

#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/mem.h>
#include <libavutil/pixdesc.h>
#include <libavutil/rational.h>
#include <libswresample/swresample.h>
#include <libswscale/swscale.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct TaptionFFmpegDecodeBridgeContext {
    AVFormatContext *formatContext;
    AVCodecContext *codecContext;
    const AVCodec *codec;
    AVFrame *decodedFrame;
    AVPacket *packet;
    struct SwsContext *swsContext;
    int videoStreamIndex;
    int decodedFrameCount;
    uint8_t *bgraBuffer;
    int bgraBufferSize;
    int bgraStride;
    TaptionFFmpegDecodeBridgeProbeResult result;
} TaptionFFmpegDecodeBridgeContext;

typedef struct TaptionFFmpegDecodeBridgeAudioContext {
    AVFormatContext *formatContext;
    AVCodecContext *codecContext;
    const AVCodec *codec;
    AVFrame *decodedFrame;
    AVPacket *packet;
    SwrContext *swrContext;
    uint8_t *s16Buffer;
    unsigned int s16BufferCapacity;
    int audioStreamIndex;
    int decodedFrameCount;
    int64_t decodedSampleCount;
    TaptionFFmpegDecodeBridgeAudioProbeResult result;
} TaptionFFmpegDecodeBridgeAudioContext;

typedef struct TaptionFFmpegDecodeBridgeBGRAOutputContext {
    TaptionFFmpegDecodeBridgeFrameCallback callback;
    void *opaque;
} TaptionFFmpegDecodeBridgeBGRAOutputContext;

typedef struct TaptionFFmpegDecodeBridgeNV12OutputContext {
    TaptionFFmpegDecodeBridgeNV12FrameCallback acquireCallback;
    TaptionFFmpegDecodeBridgeNV12FrameCallback commitCallback;
    void *opaque;
} TaptionFFmpegDecodeBridgeNV12OutputContext;

typedef int32_t (*TaptionFFmpegDecodeBridgeInternalFrameDelivery)(
    TaptionFFmpegDecodeBridgeContext *context,
    const AVStream *stream,
    void *outputContext,
    char *errorBuffer,
    int32_t errorBufferCapacity
);

static void taption_ffmpeg_set_error(
    char *errorBuffer,
    int32_t errorBufferCapacity,
    const char *message
) {
    if (errorBuffer == NULL || errorBufferCapacity <= 0) {
        return;
    }
    if (message == NULL) {
        message = "Unknown FFmpeg decode bridge error.";
    }
    snprintf(errorBuffer, (size_t)errorBufferCapacity, "%s", message);
}

static void taption_ffmpeg_set_av_error(
    char *errorBuffer,
    int32_t errorBufferCapacity,
    const char *prefix,
    int avError
) {
    if (errorBuffer == NULL || errorBufferCapacity <= 0) {
        return;
    }
    char details[AV_ERROR_MAX_STRING_SIZE] = {0};
    av_strerror(avError, details, sizeof(details));
    snprintf(errorBuffer, (size_t)errorBufferCapacity, "%s: %s", prefix, details);
}

static const AVInputFormat *taption_ffmpeg_forced_input_format(const char *sourcePath) {
    if (sourcePath == NULL) {
        return NULL;
    }
    const char *extension = strrchr(sourcePath, '.');
    if (extension != NULL && strcmp(extension, ".vc1") == 0) {
        return av_find_input_format("vc1");
    }
    return NULL;
}

static int taption_ffmpeg_source_path_has_extension(const char *sourcePath, const char *extension) {
    if (sourcePath == NULL || extension == NULL) {
        return 0;
    }
    const char *pathExtension = strrchr(sourcePath, '.');
    return pathExtension != NULL && strcmp(pathExtension, extension) == 0;
}

static int taption_ffmpeg_is_start_code(const uint8_t *buffer, size_t offset, size_t size, uint8_t code) {
    return offset + 4 <= size
        && buffer[offset] == 0x00
        && buffer[offset + 1] == 0x00
        && buffer[offset + 2] == 0x01
        && buffer[offset + 3] == code;
}

static int taption_ffmpeg_install_raw_vc1_extradata(
    AVCodecContext *codecContext,
    const char *sourcePath,
    char *errorBuffer,
    int32_t errorBufferCapacity
) {
    if (codecContext == NULL || !taption_ffmpeg_source_path_has_extension(sourcePath, ".vc1")) {
        return 0;
    }

    FILE *file = fopen(sourcePath, "rb");
    if (file == NULL) {
        taption_ffmpeg_set_error(errorBuffer, errorBufferCapacity, "Failed to open raw VC-1 input while building extradata.");
        return -1;
    }

    uint8_t headerBuffer[4096];
    size_t bytesRead = fread(headerBuffer, 1, sizeof(headerBuffer), file);
    fclose(file);
    if (bytesRead < 16) {
        taption_ffmpeg_set_error(errorBuffer, errorBufferCapacity, "Raw VC-1 input was too small to build extradata.");
        return -1;
    }

    size_t sequenceOffset = SIZE_MAX;
    size_t entryPointOffset = SIZE_MAX;
    size_t firstFrameOffset = SIZE_MAX;
    for (size_t offset = 0; offset + 4 <= bytesRead; offset++) {
        if (taption_ffmpeg_is_start_code(headerBuffer, offset, bytesRead, 0x0F) && sequenceOffset == SIZE_MAX) {
            sequenceOffset = offset;
        } else if (taption_ffmpeg_is_start_code(headerBuffer, offset, bytesRead, 0x0E) && entryPointOffset == SIZE_MAX) {
            entryPointOffset = offset;
        } else if (taption_ffmpeg_is_start_code(headerBuffer, offset, bytesRead, 0x0D)) {
            firstFrameOffset = offset;
            break;
        }
    }

    if (sequenceOffset == SIZE_MAX || entryPointOffset == SIZE_MAX || firstFrameOffset == SIZE_MAX
        || sequenceOffset >= entryPointOffset || entryPointOffset >= firstFrameOffset) {
        taption_ffmpeg_set_error(errorBuffer, errorBufferCapacity, "Raw VC-1 sequence/entrypoint extradata was not found.");
        return -1;
    }

    size_t extradataSize = firstFrameOffset - sequenceOffset;
    uint8_t *extradata = av_mallocz(extradataSize + AV_INPUT_BUFFER_PADDING_SIZE);
    if (extradata == NULL) {
        taption_ffmpeg_set_error(errorBuffer, errorBufferCapacity, "Failed to allocate raw VC-1 extradata.");
        return -1;
    }
    memcpy(extradata, headerBuffer + sequenceOffset, extradataSize);

    av_freep(&codecContext->extradata);
    codecContext->extradata = extradata;
    codecContext->extradata_size = (int)extradataSize;
    return 0;
}

static double taption_ffmpeg_rational_to_double(AVRational value) {
    if (value.num <= 0 || value.den <= 0) {
        return 0.0;
    }
    return av_q2d(value);
}

static double taption_ffmpeg_seconds_from_timestamp(int64_t timestamp, AVRational timeBase) {
    if (timestamp == AV_NOPTS_VALUE || timeBase.num <= 0 || timeBase.den <= 0) {
        return -1.0;
    }
    return (double)timestamp * av_q2d(timeBase);
}

static void taption_ffmpeg_update_result(
    TaptionFFmpegDecodeBridgeContext *context,
    const AVStream *stream
) {
    if (context == NULL || context->codecContext == NULL) {
        return;
    }

    TaptionFFmpegDecodeBridgeProbeResult *result = &context->result;
    result->width = context->codecContext->width;
    result->height = context->codecContext->height;
    result->frameCount = context->decodedFrameCount;
    result->codecID = context->codecContext->codec_id;
    result->pixelFormat = context->codecContext->pix_fmt;
    result->sampleAspectRatioNumerator = 1;
    result->sampleAspectRatioDenominator = 1;

    const char *codecName = avcodec_get_name(context->codecContext->codec_id);
    const char *pixelFormatName = av_get_pix_fmt_name(context->codecContext->pix_fmt);
    snprintf(result->codecName, sizeof(result->codecName), "%s", codecName != NULL ? codecName : "unknown");
    snprintf(
        result->pixelFormatName,
        sizeof(result->pixelFormatName),
        "%s",
        pixelFormatName != NULL ? pixelFormatName : "unknown"
    );

    if (stream != NULL) {
        AVRational sampleAspectRatio = stream->sample_aspect_ratio;
        if ((sampleAspectRatio.num <= 0 || sampleAspectRatio.den <= 0)
            && context->decodedFrame != NULL) {
            sampleAspectRatio = context->decodedFrame->sample_aspect_ratio;
        }
        if (sampleAspectRatio.num <= 0 || sampleAspectRatio.den <= 0) {
            sampleAspectRatio = context->codecContext->sample_aspect_ratio;
        }
        if (sampleAspectRatio.num > 0 && sampleAspectRatio.den > 0) {
            result->sampleAspectRatioNumerator = sampleAspectRatio.num;
            result->sampleAspectRatioDenominator = sampleAspectRatio.den;
        }
        result->averageFrameRate = taption_ffmpeg_rational_to_double(stream->avg_frame_rate);
        if (result->averageFrameRate <= 0.0) {
            result->averageFrameRate = taption_ffmpeg_rational_to_double(stream->r_frame_rate);
        }
        if (stream->duration != AV_NOPTS_VALUE) {
            result->durationSeconds = taption_ffmpeg_seconds_from_timestamp(stream->duration, stream->time_base);
        } else if (context->formatContext != NULL && context->formatContext->duration != AV_NOPTS_VALUE) {
            result->durationSeconds = (double)context->formatContext->duration / (double)AV_TIME_BASE;
        }
    }
}

static void taption_ffmpeg_close_context(TaptionFFmpegDecodeBridgeContext *context) {
    if (context == NULL) {
        return;
    }
    if (context->bgraBuffer != NULL) {
        free(context->bgraBuffer);
    }
    if (context->swsContext != NULL) {
        sws_freeContext(context->swsContext);
    }
    if (context->packet != NULL) {
        av_packet_free(&context->packet);
    }
    if (context->decodedFrame != NULL) {
        av_frame_free(&context->decodedFrame);
    }
    if (context->codecContext != NULL) {
        avcodec_free_context(&context->codecContext);
    }
    if (context->formatContext != NULL) {
        avformat_close_input(&context->formatContext);
    }
}

static int32_t taption_ffmpeg_open_context(
    const char *sourcePath,
    TaptionFFmpegDecodeBridgeContext *context,
    char *errorBuffer,
    int32_t errorBufferCapacity
) {
    if (sourcePath == NULL || context == NULL) {
        taption_ffmpeg_set_error(errorBuffer, errorBufferCapacity, "Missing source path or decode context.");
        return TaptionFFmpegDecodeBridgeStatusInvalidArgument;
    }

    memset(context, 0, sizeof(*context));
    context->videoStreamIndex = -1;

    av_log_set_level(AV_LOG_ERROR);

    const AVInputFormat *forcedInputFormat = taption_ffmpeg_forced_input_format(sourcePath);
    int status = avformat_open_input(&context->formatContext, sourcePath, forcedInputFormat, NULL);
    if (status < 0) {
        taption_ffmpeg_set_av_error(errorBuffer, errorBufferCapacity, "Failed to open FFmpeg input", status);
        return TaptionFFmpegDecodeBridgeStatusOpenInputFailed;
    }

    status = avformat_find_stream_info(context->formatContext, NULL);
    if (status < 0) {
        taption_ffmpeg_set_av_error(errorBuffer, errorBufferCapacity, "Failed to read FFmpeg stream info", status);
        return TaptionFFmpegDecodeBridgeStatusStreamInfoFailed;
    }

    status = av_find_best_stream(
        context->formatContext,
        AVMEDIA_TYPE_VIDEO,
        -1,
        -1,
        &context->codec,
        0
    );
    if (status < 0) {
        taption_ffmpeg_set_error(errorBuffer, errorBufferCapacity, "No decodable video stream was found.");
        return TaptionFFmpegDecodeBridgeStatusVideoStreamMissing;
    }
    context->videoStreamIndex = status;

    AVStream *stream = context->formatContext->streams[context->videoStreamIndex];
    context->codec = avcodec_find_decoder(stream->codecpar->codec_id);
    if (context->codec == NULL) {
        taption_ffmpeg_set_error(errorBuffer, errorBufferCapacity, "No FFmpeg decoder is available for the selected video stream.");
        return TaptionFFmpegDecodeBridgeStatusDecoderMissing;
    }

    context->codecContext = avcodec_alloc_context3(context->codec);
    if (context->codecContext == NULL) {
        taption_ffmpeg_set_error(errorBuffer, errorBufferCapacity, "Failed to allocate the FFmpeg decoder context.");
        return TaptionFFmpegDecodeBridgeStatusDecoderOpenFailed;
    }

    status = avcodec_parameters_to_context(context->codecContext, stream->codecpar);
    if (status < 0) {
        taption_ffmpeg_set_av_error(errorBuffer, errorBufferCapacity, "Failed to copy FFmpeg decoder parameters", status);
        return TaptionFFmpegDecodeBridgeStatusDecoderOpenFailed;
    }
    if (taption_ffmpeg_install_raw_vc1_extradata(
        context->codecContext,
        sourcePath,
        errorBuffer,
        errorBufferCapacity
    ) < 0) {
        return TaptionFFmpegDecodeBridgeStatusDecoderOpenFailed;
    }

    status = avcodec_open2(context->codecContext, context->codec, NULL);
    if (status < 0) {
        taption_ffmpeg_set_av_error(errorBuffer, errorBufferCapacity, "Failed to open the FFmpeg decoder", status);
        return TaptionFFmpegDecodeBridgeStatusDecoderOpenFailed;
    }

    context->decodedFrame = av_frame_alloc();
    context->packet = av_packet_alloc();
    if (context->decodedFrame == NULL || context->packet == NULL) {
        taption_ffmpeg_set_error(errorBuffer, errorBufferCapacity, "Failed to allocate FFmpeg frame or packet.");
        return TaptionFFmpegDecodeBridgeStatusDecodeFailed;
    }

    taption_ffmpeg_update_result(context, stream);
    return TaptionFFmpegDecodeBridgeStatusOK;
}

static int32_t taption_ffmpeg_deliver_decoded_bgra_frame(
    TaptionFFmpegDecodeBridgeContext *context,
    const AVStream *stream,
    void *rawOutputContext,
    char *errorBuffer,
    int32_t errorBufferCapacity
) {
    TaptionFFmpegDecodeBridgeBGRAOutputContext *outputContext =
        (TaptionFFmpegDecodeBridgeBGRAOutputContext *)rawOutputContext;
    int width = context->decodedFrame->width;
    int height = context->decodedFrame->height;
    if (width <= 0 || height <= 0) {
        width = context->codecContext->width;
        height = context->codecContext->height;
    }
    if (width <= 0 || height <= 0) {
        taption_ffmpeg_set_error(errorBuffer, errorBufferCapacity, "Decoded FFmpeg frame did not report a valid size.");
        return TaptionFFmpegDecodeBridgeStatusDecodeFailed;
    }

    const enum AVPixelFormat sourceFormat = (enum AVPixelFormat)context->decodedFrame->format;
    context->swsContext = sws_getCachedContext(
        context->swsContext,
        width,
        height,
        sourceFormat,
        width,
        height,
        AV_PIX_FMT_BGRA,
        SWS_BILINEAR,
        NULL,
        NULL,
        NULL
    );
    if (context->swsContext == NULL) {
        taption_ffmpeg_set_error(errorBuffer, errorBufferCapacity, "Failed to create FFmpeg BGRA scaler.");
        return TaptionFFmpegDecodeBridgeStatusScaleFailed;
    }

    const int requiredStride = width * 4;
    const int requiredSize = requiredStride * height;
    if (requiredSize <= 0) {
        taption_ffmpeg_set_error(errorBuffer, errorBufferCapacity, "Decoded FFmpeg frame has an invalid BGRA buffer size.");
        return TaptionFFmpegDecodeBridgeStatusScaleFailed;
    }
    if (context->bgraBufferSize < requiredSize) {
        uint8_t *newBuffer = (uint8_t *)realloc(context->bgraBuffer, (size_t)requiredSize);
        if (newBuffer == NULL) {
            taption_ffmpeg_set_error(errorBuffer, errorBufferCapacity, "Failed to allocate the FFmpeg BGRA buffer.");
            return TaptionFFmpegDecodeBridgeStatusScaleFailed;
        }
        context->bgraBuffer = newBuffer;
        context->bgraBufferSize = requiredSize;
        context->bgraStride = requiredStride;
    }

    uint8_t *destinationData[4] = {context->bgraBuffer, NULL, NULL, NULL};
    int destinationLineSize[4] = {context->bgraStride, 0, 0, 0};
    int scaledHeight = sws_scale(
        context->swsContext,
        (const uint8_t * const *)context->decodedFrame->data,
        context->decodedFrame->linesize,
        0,
        height,
        destinationData,
        destinationLineSize
    );
    if (scaledHeight <= 0) {
        taption_ffmpeg_set_error(errorBuffer, errorBufferCapacity, "FFmpeg failed to scale decoded frame to BGRA.");
        return TaptionFFmpegDecodeBridgeStatusScaleFailed;
    }

    double ptsSeconds = taption_ffmpeg_seconds_from_timestamp(
        context->decodedFrame->best_effort_timestamp,
        stream->time_base
    );
    if (ptsSeconds < 0.0) {
        double fps = context->result.averageFrameRate > 0.0 ? context->result.averageFrameRate : 30.0;
        ptsSeconds = (double)context->decodedFrameCount / fps;
    }

    TaptionFFmpegDecodeBridgeFrame callbackFrame;
    callbackFrame.frameIndex = context->decodedFrameCount;
    callbackFrame.width = width;
    callbackFrame.height = height;
    callbackFrame.bytesPerRow = context->bgraStride;
    callbackFrame.ptsSeconds = ptsSeconds;
    callbackFrame.bgraBytes = context->bgraBuffer;

    if (outputContext != NULL && outputContext->callback != NULL) {
        int32_t callbackStatus = outputContext->callback(&callbackFrame, outputContext->opaque);
        if (callbackStatus != 0) {
            taption_ffmpeg_set_error(errorBuffer, errorBufferCapacity, "The FFmpeg decode bridge frame callback failed.");
            return TaptionFFmpegDecodeBridgeStatusCallbackFailed;
        }
    }

    context->decodedFrameCount += 1;
    taption_ffmpeg_update_result(context, stream);
    return TaptionFFmpegDecodeBridgeStatusOK;
}

static int32_t taption_ffmpeg_deliver_decoded_nv12_frame(
    TaptionFFmpegDecodeBridgeContext *context,
    const AVStream *stream,
    void *rawOutputContext,
    char *errorBuffer,
    int32_t errorBufferCapacity
) {
    TaptionFFmpegDecodeBridgeNV12OutputContext *outputContext =
        (TaptionFFmpegDecodeBridgeNV12OutputContext *)rawOutputContext;
    if (outputContext == NULL || outputContext->acquireCallback == NULL || outputContext->commitCallback == NULL) {
        taption_ffmpeg_set_error(errorBuffer, errorBufferCapacity, "The FFmpeg NV12 output callbacks are missing.");
        return TaptionFFmpegDecodeBridgeStatusInvalidArgument;
    }

    int width = context->decodedFrame->width;
    int height = context->decodedFrame->height;
    if (width <= 0 || height <= 0) {
        width = context->codecContext->width;
        height = context->codecContext->height;
    }
    if (width <= 0 || height <= 0 || (width & 1) != 0 || (height & 1) != 0) {
        taption_ffmpeg_set_error(errorBuffer, errorBufferCapacity, "Decoded FFmpeg frame is not valid for direct NV12 output.");
        return TaptionFFmpegDecodeBridgeStatusScaleFailed;
    }

    double ptsSeconds = taption_ffmpeg_seconds_from_timestamp(
        context->decodedFrame->best_effort_timestamp,
        stream->time_base
    );
    if (ptsSeconds < 0.0) {
        double fps = context->result.averageFrameRate > 0.0 ? context->result.averageFrameRate : 30.0;
        ptsSeconds = (double)context->decodedFrameCount / fps;
    }

    TaptionFFmpegDecodeBridgeWritableNV12Frame outputFrame;
    memset(&outputFrame, 0, sizeof(outputFrame));
    outputFrame.frameIndex = context->decodedFrameCount;
    outputFrame.width = width;
    outputFrame.height = height;
    outputFrame.ptsSeconds = ptsSeconds;
    if (outputContext->acquireCallback(&outputFrame, outputContext->opaque) != 0
        || outputFrame.yBytes == NULL
        || outputFrame.uvBytes == NULL
        || outputFrame.yBytesPerRow < width
        || outputFrame.uvBytesPerRow < width) {
        taption_ffmpeg_set_error(errorBuffer, errorBufferCapacity, "The FFmpeg NV12 output buffer could not be acquired.");
        return TaptionFFmpegDecodeBridgeStatusCallbackFailed;
    }

    const enum AVPixelFormat sourceFormat = (enum AVPixelFormat)context->decodedFrame->format;
    context->swsContext = sws_getCachedContext(
        context->swsContext,
        width,
        height,
        sourceFormat,
        width,
        height,
        AV_PIX_FMT_NV12,
        SWS_BILINEAR,
        NULL,
        NULL,
        NULL
    );
    if (context->swsContext == NULL) {
        taption_ffmpeg_set_error(errorBuffer, errorBufferCapacity, "Failed to create FFmpeg NV12 scaler.");
        return TaptionFFmpegDecodeBridgeStatusScaleFailed;
    }

    uint8_t *destinationData[4] = {outputFrame.yBytes, outputFrame.uvBytes, NULL, NULL};
    int destinationLineSize[4] = {outputFrame.yBytesPerRow, outputFrame.uvBytesPerRow, 0, 0};
    int scaledHeight = sws_scale(
        context->swsContext,
        (const uint8_t * const *)context->decodedFrame->data,
        context->decodedFrame->linesize,
        0,
        height,
        destinationData,
        destinationLineSize
    );
    if (scaledHeight != height) {
        taption_ffmpeg_set_error(errorBuffer, errorBufferCapacity, "FFmpeg failed to scale decoded frame directly to NV12.");
        return TaptionFFmpegDecodeBridgeStatusScaleFailed;
    }
    if (outputContext->commitCallback(&outputFrame, outputContext->opaque) != 0) {
        taption_ffmpeg_set_error(errorBuffer, errorBufferCapacity, "The FFmpeg NV12 frame callback failed.");
        return TaptionFFmpegDecodeBridgeStatusCallbackFailed;
    }

    context->decodedFrameCount += 1;
    taption_ffmpeg_update_result(context, stream);
    return TaptionFFmpegDecodeBridgeStatusOK;
}

static int32_t taption_ffmpeg_receive_frames(
    TaptionFFmpegDecodeBridgeContext *context,
    const AVStream *stream,
    int32_t maximumFrameCount,
    TaptionFFmpegDecodeBridgeInternalFrameDelivery delivery,
    void *outputContext,
    char *errorBuffer,
    int32_t errorBufferCapacity
) {
    while (1) {
        int status = avcodec_receive_frame(context->codecContext, context->decodedFrame);
        if (status == AVERROR(EAGAIN) || status == AVERROR_EOF) {
            return TaptionFFmpegDecodeBridgeStatusOK;
        }
        if (status < 0) {
            taption_ffmpeg_set_av_error(errorBuffer, errorBufferCapacity, "FFmpeg failed while receiving decoded frames", status);
            return TaptionFFmpegDecodeBridgeStatusDecodeFailed;
        }

        int32_t delivered = delivery(
            context,
            stream,
            outputContext,
            errorBuffer,
            errorBufferCapacity
        );
        av_frame_unref(context->decodedFrame);
        if (delivered != TaptionFFmpegDecodeBridgeStatusOK) {
            return delivered;
        }
        if (maximumFrameCount > 0 && context->decodedFrameCount >= maximumFrameCount) {
            return TaptionFFmpegDecodeBridgeStatusOK;
        }
    }
}

static int32_t taption_ffmpeg_decode_bridge_decode_video(
    const char *sourcePath,
    int32_t maximumFrameCount,
    TaptionFFmpegDecodeBridgeInternalFrameDelivery delivery,
    void *outputContext,
    TaptionFFmpegDecodeBridgeProbeResult *result,
    char *errorBuffer,
    int32_t errorBufferCapacity
) {
    TaptionFFmpegDecodeBridgeContext context;
    int32_t status = taption_ffmpeg_open_context(
        sourcePath,
        &context,
        errorBuffer,
        errorBufferCapacity
    );
    if (status != TaptionFFmpegDecodeBridgeStatusOK) {
        taption_ffmpeg_close_context(&context);
        return status;
    }

    AVStream *stream = context.formatContext->streams[context.videoStreamIndex];

    while ((maximumFrameCount <= 0 || context.decodedFrameCount < maximumFrameCount)
           && av_read_frame(context.formatContext, context.packet) >= 0) {
        if (context.packet->stream_index == context.videoStreamIndex) {
            int sendStatus = avcodec_send_packet(context.codecContext, context.packet);
            av_packet_unref(context.packet);
            if (sendStatus < 0) {
                taption_ffmpeg_set_av_error(errorBuffer, errorBufferCapacity, "FFmpeg failed while sending a packet to the decoder", sendStatus);
                taption_ffmpeg_close_context(&context);
                return TaptionFFmpegDecodeBridgeStatusDecodeFailed;
            }

            status = taption_ffmpeg_receive_frames(
                &context,
                stream,
                maximumFrameCount,
                delivery,
                outputContext,
                errorBuffer,
                errorBufferCapacity
            );
            if (status != TaptionFFmpegDecodeBridgeStatusOK) {
                taption_ffmpeg_close_context(&context);
                return status;
            }
        } else {
            av_packet_unref(context.packet);
        }
    }

    int flushStatus = avcodec_send_packet(context.codecContext, NULL);
    if (flushStatus >= 0) {
        status = taption_ffmpeg_receive_frames(
            &context,
            stream,
            maximumFrameCount,
            delivery,
            outputContext,
            errorBuffer,
            errorBufferCapacity
        );
    }

    if (result != NULL) {
        *result = context.result;
    }
    int decodedFrameCount = context.decodedFrameCount;
    taption_ffmpeg_close_context(&context);

    if (status != TaptionFFmpegDecodeBridgeStatusOK) {
        return status;
    }
    if (decodedFrameCount <= 0) {
        taption_ffmpeg_set_error(errorBuffer, errorBufferCapacity, "FFmpeg decode bridge did not produce video frames.");
        return TaptionFFmpegDecodeBridgeStatusNoFramesDecoded;
    }
    return TaptionFFmpegDecodeBridgeStatusOK;
}

int32_t taption_ffmpeg_decode_bridge_decode_video_to_bgra(
    const char *sourcePath,
    int32_t maximumFrameCount,
    TaptionFFmpegDecodeBridgeFrameCallback callback,
    void *opaque,
    TaptionFFmpegDecodeBridgeProbeResult *result,
    char *errorBuffer,
    int32_t errorBufferCapacity
) {
    TaptionFFmpegDecodeBridgeBGRAOutputContext outputContext = {callback, opaque};
    return taption_ffmpeg_decode_bridge_decode_video(
        sourcePath,
        maximumFrameCount,
        taption_ffmpeg_deliver_decoded_bgra_frame,
        &outputContext,
        result,
        errorBuffer,
        errorBufferCapacity
    );
}

int32_t taption_ffmpeg_decode_bridge_decode_video_to_nv12(
    const char *sourcePath,
    int32_t maximumFrameCount,
    TaptionFFmpegDecodeBridgeNV12FrameCallback acquireCallback,
    TaptionFFmpegDecodeBridgeNV12FrameCallback commitCallback,
    void *opaque,
    TaptionFFmpegDecodeBridgeProbeResult *result,
    char *errorBuffer,
    int32_t errorBufferCapacity
) {
    TaptionFFmpegDecodeBridgeNV12OutputContext outputContext = {
        acquireCallback,
        commitCallback,
        opaque
    };
    return taption_ffmpeg_decode_bridge_decode_video(
        sourcePath,
        maximumFrameCount,
        taption_ffmpeg_deliver_decoded_nv12_frame,
        &outputContext,
        result,
        errorBuffer,
        errorBufferCapacity
    );
}

int32_t taption_ffmpeg_decode_bridge_probe_video(
    const char *sourcePath,
    TaptionFFmpegDecodeBridgeProbeResult *result,
    char *errorBuffer,
    int32_t errorBufferCapacity
) {
    return taption_ffmpeg_decode_bridge_decode_video_to_bgra(
        sourcePath,
        1,
        NULL,
        NULL,
        result,
        errorBuffer,
        errorBufferCapacity
    );
}

static void taption_ffmpeg_close_audio_context(TaptionFFmpegDecodeBridgeAudioContext *context) {
    if (context == NULL) {
        return;
    }
    if (context->s16Buffer != NULL) {
        av_freep(&context->s16Buffer);
    }
    if (context->swrContext != NULL) {
        swr_free(&context->swrContext);
    }
    if (context->packet != NULL) {
        av_packet_free(&context->packet);
    }
    if (context->decodedFrame != NULL) {
        av_frame_free(&context->decodedFrame);
    }
    if (context->codecContext != NULL) {
        avcodec_free_context(&context->codecContext);
    }
    if (context->formatContext != NULL) {
        avformat_close_input(&context->formatContext);
    }
}

static void taption_ffmpeg_update_audio_result(
    TaptionFFmpegDecodeBridgeAudioContext *context,
    const AVStream *stream
) {
    if (context == NULL || context->codecContext == NULL) {
        return;
    }

    TaptionFFmpegDecodeBridgeAudioProbeResult *result = &context->result;
    result->sampleRate = context->codecContext->sample_rate;
    result->channelCount = context->codecContext->ch_layout.nb_channels;
    result->sampleFormat = AV_SAMPLE_FMT_S16;
    result->codecID = context->codecContext->codec_id;
    result->sampleCount = context->decodedSampleCount;

    const char *codecName = avcodec_get_name(context->codecContext->codec_id);
    const char *sampleFormatName = av_get_sample_fmt_name(AV_SAMPLE_FMT_S16);
    snprintf(result->codecName, sizeof(result->codecName), "%s", codecName != NULL ? codecName : "unknown");
    snprintf(
        result->sampleFormatName,
        sizeof(result->sampleFormatName),
        "%s",
        sampleFormatName != NULL ? sampleFormatName : "unknown"
    );

    if (stream != NULL) {
        if (stream->duration != AV_NOPTS_VALUE) {
            result->durationSeconds = taption_ffmpeg_seconds_from_timestamp(stream->duration, stream->time_base);
        } else if (context->formatContext != NULL && context->formatContext->duration != AV_NOPTS_VALUE) {
            result->durationSeconds = (double)context->formatContext->duration / (double)AV_TIME_BASE;
        }
    }
}

static int32_t taption_ffmpeg_open_audio_context(
    const char *sourcePath,
    TaptionFFmpegDecodeBridgeAudioContext *context,
    char *errorBuffer,
    int32_t errorBufferCapacity
) {
    if (sourcePath == NULL || context == NULL) {
        taption_ffmpeg_set_error(errorBuffer, errorBufferCapacity, "Missing source path or audio decode context.");
        return TaptionFFmpegDecodeBridgeStatusInvalidArgument;
    }

    memset(context, 0, sizeof(*context));
    context->audioStreamIndex = -1;
    av_log_set_level(AV_LOG_ERROR);

    int status = avformat_open_input(&context->formatContext, sourcePath, NULL, NULL);
    if (status < 0) {
        taption_ffmpeg_set_av_error(errorBuffer, errorBufferCapacity, "Failed to open FFmpeg audio input", status);
        return TaptionFFmpegDecodeBridgeStatusOpenInputFailed;
    }
    status = avformat_find_stream_info(context->formatContext, NULL);
    if (status < 0) {
        taption_ffmpeg_set_av_error(errorBuffer, errorBufferCapacity, "Failed to read FFmpeg audio stream info", status);
        return TaptionFFmpegDecodeBridgeStatusStreamInfoFailed;
    }

    status = av_find_best_stream(
        context->formatContext,
        AVMEDIA_TYPE_AUDIO,
        -1,
        -1,
        &context->codec,
        0
    );
    if (status < 0) {
        taption_ffmpeg_set_error(errorBuffer, errorBufferCapacity, "No decodable audio stream was found.");
        return TaptionFFmpegDecodeBridgeStatusAudioStreamMissing;
    }
    context->audioStreamIndex = status;

    AVStream *stream = context->formatContext->streams[context->audioStreamIndex];
    context->codec = avcodec_find_decoder(stream->codecpar->codec_id);
    if (context->codec == NULL) {
        taption_ffmpeg_set_error(errorBuffer, errorBufferCapacity, "No FFmpeg decoder is available for the selected audio stream.");
        return TaptionFFmpegDecodeBridgeStatusDecoderMissing;
    }
    context->codecContext = avcodec_alloc_context3(context->codec);
    if (context->codecContext == NULL) {
        taption_ffmpeg_set_error(errorBuffer, errorBufferCapacity, "Failed to allocate the FFmpeg audio decoder context.");
        return TaptionFFmpegDecodeBridgeStatusDecoderOpenFailed;
    }
    status = avcodec_parameters_to_context(context->codecContext, stream->codecpar);
    if (status < 0) {
        taption_ffmpeg_set_av_error(errorBuffer, errorBufferCapacity, "Failed to copy FFmpeg audio decoder parameters", status);
        return TaptionFFmpegDecodeBridgeStatusDecoderOpenFailed;
    }
    status = avcodec_open2(context->codecContext, context->codec, NULL);
    if (status < 0) {
        taption_ffmpeg_set_av_error(errorBuffer, errorBufferCapacity, "Failed to open the FFmpeg audio decoder", status);
        return TaptionFFmpegDecodeBridgeStatusDecoderOpenFailed;
    }

    AVChannelLayout outputChannelLayout;
    av_channel_layout_default(
        &outputChannelLayout,
        context->codecContext->ch_layout.nb_channels
    );
    status = swr_alloc_set_opts2(
        &context->swrContext,
        &outputChannelLayout,
        AV_SAMPLE_FMT_S16,
        context->codecContext->sample_rate,
        &context->codecContext->ch_layout,
        context->codecContext->sample_fmt,
        context->codecContext->sample_rate,
        0,
        NULL
    );
    av_channel_layout_uninit(&outputChannelLayout);
    if (status < 0 || context->swrContext == NULL) {
        taption_ffmpeg_set_av_error(
            errorBuffer,
            errorBufferCapacity,
            "Failed to configure FFmpeg packed S16 audio conversion",
            status
        );
        return TaptionFFmpegDecodeBridgeStatusAudioSampleFormatUnsupported;
    }
    status = swr_init(context->swrContext);
    if (status < 0) {
        taption_ffmpeg_set_av_error(
            errorBuffer,
            errorBufferCapacity,
            "Failed to initialize FFmpeg packed S16 audio conversion",
            status
        );
        return TaptionFFmpegDecodeBridgeStatusAudioSampleFormatUnsupported;
    }

    context->decodedFrame = av_frame_alloc();
    context->packet = av_packet_alloc();
    if (context->decodedFrame == NULL || context->packet == NULL) {
        taption_ffmpeg_set_error(errorBuffer, errorBufferCapacity, "Failed to allocate FFmpeg audio frame or packet.");
        return TaptionFFmpegDecodeBridgeStatusDecodeFailed;
    }
    taption_ffmpeg_update_audio_result(context, stream);
    return TaptionFFmpegDecodeBridgeStatusOK;
}

static int32_t taption_ffmpeg_receive_audio_frames(
    TaptionFFmpegDecodeBridgeAudioContext *context,
    const AVStream *stream,
    TaptionFFmpegDecodeBridgeAudioFrameCallback callback,
    void *opaque,
    char *errorBuffer,
    int32_t errorBufferCapacity
) {
    while (1) {
        int status = avcodec_receive_frame(context->codecContext, context->decodedFrame);
        if (status == AVERROR(EAGAIN) || status == AVERROR_EOF) {
            return TaptionFFmpegDecodeBridgeStatusOK;
        }
        if (status < 0) {
            taption_ffmpeg_set_av_error(errorBuffer, errorBufferCapacity, "FFmpeg failed while receiving decoded audio frames", status);
            return TaptionFFmpegDecodeBridgeStatusDecodeFailed;
        }

        int channelCount = context->codecContext->ch_layout.nb_channels;
        int maximumOutputSampleCount = swr_get_out_samples(
            context->swrContext,
            context->decodedFrame->nb_samples
        );
        int requiredBufferSize = av_samples_get_buffer_size(
            NULL,
            channelCount,
            maximumOutputSampleCount,
            AV_SAMPLE_FMT_S16,
            1
        );
        if (channelCount <= 0 || maximumOutputSampleCount <= 0 || requiredBufferSize <= 0) {
            taption_ffmpeg_set_error(errorBuffer, errorBufferCapacity, "FFmpeg audio conversion reported an invalid buffer size.");
            av_frame_unref(context->decodedFrame);
            return TaptionFFmpegDecodeBridgeStatusAudioSampleFormatUnsupported;
        }
        if ((unsigned int)requiredBufferSize > context->s16BufferCapacity) {
            av_fast_malloc(
                &context->s16Buffer,
                &context->s16BufferCapacity,
                (size_t)requiredBufferSize
            );
        }
        if (context->s16Buffer == NULL) {
            taption_ffmpeg_set_error(errorBuffer, errorBufferCapacity, "Failed to allocate FFmpeg packed S16 audio output.");
            av_frame_unref(context->decodedFrame);
            return TaptionFFmpegDecodeBridgeStatusAudioSampleFormatUnsupported;
        }

        uint8_t *outputData[1] = {context->s16Buffer};
        int convertedSampleCount = swr_convert(
            context->swrContext,
            outputData,
            maximumOutputSampleCount,
            (const uint8_t **)context->decodedFrame->extended_data,
            context->decodedFrame->nb_samples
        );
        if (convertedSampleCount < 0) {
            taption_ffmpeg_set_av_error(
                errorBuffer,
                errorBufferCapacity,
                "FFmpeg failed to convert decoded audio to packed S16",
                convertedSampleCount
            );
            av_frame_unref(context->decodedFrame);
            return TaptionFFmpegDecodeBridgeStatusAudioSampleFormatUnsupported;
        }

        double ptsSeconds = taption_ffmpeg_seconds_from_timestamp(
            context->decodedFrame->best_effort_timestamp,
            stream->time_base
        );
        if (ptsSeconds < 0.0) {
            ptsSeconds = (double)context->decodedSampleCount / (double)context->codecContext->sample_rate;
        }

        TaptionFFmpegDecodeBridgeAudioFrame callbackFrame;
        callbackFrame.frameIndex = context->decodedFrameCount;
        callbackFrame.sampleRate = context->codecContext->sample_rate;
        callbackFrame.channelCount = channelCount;
        callbackFrame.sampleCount = convertedSampleCount;
        callbackFrame.ptsSeconds = ptsSeconds;
        callbackFrame.interleavedS16Samples = (const int16_t *)context->s16Buffer;

        if (callback != NULL && callback(&callbackFrame, opaque) != 0) {
            taption_ffmpeg_set_error(errorBuffer, errorBufferCapacity, "The FFmpeg audio decode bridge callback failed.");
            av_frame_unref(context->decodedFrame);
            return TaptionFFmpegDecodeBridgeStatusCallbackFailed;
        }

        context->decodedFrameCount += 1;
        context->decodedSampleCount += convertedSampleCount;
        taption_ffmpeg_update_audio_result(context, stream);
        av_frame_unref(context->decodedFrame);
    }
}

int32_t taption_ffmpeg_decode_bridge_decode_audio_s16(
    const char *sourcePath,
    TaptionFFmpegDecodeBridgeAudioFrameCallback callback,
    void *opaque,
    TaptionFFmpegDecodeBridgeAudioProbeResult *result,
    char *errorBuffer,
    int32_t errorBufferCapacity
) {
    TaptionFFmpegDecodeBridgeAudioContext context;
    int32_t status = taption_ffmpeg_open_audio_context(sourcePath, &context, errorBuffer, errorBufferCapacity);
    if (status != TaptionFFmpegDecodeBridgeStatusOK) {
        taption_ffmpeg_close_audio_context(&context);
        return status;
    }

    AVStream *stream = context.formatContext->streams[context.audioStreamIndex];
    while (av_read_frame(context.formatContext, context.packet) >= 0) {
        if (context.packet->stream_index == context.audioStreamIndex) {
            int sendStatus = avcodec_send_packet(context.codecContext, context.packet);
            av_packet_unref(context.packet);
            if (sendStatus < 0) {
                taption_ffmpeg_set_av_error(errorBuffer, errorBufferCapacity, "FFmpeg failed while sending an audio packet to the decoder", sendStatus);
                taption_ffmpeg_close_audio_context(&context);
                return TaptionFFmpegDecodeBridgeStatusDecodeFailed;
            }
            status = taption_ffmpeg_receive_audio_frames(
                &context,
                stream,
                callback,
                opaque,
                errorBuffer,
                errorBufferCapacity
            );
            if (status != TaptionFFmpegDecodeBridgeStatusOK) {
                taption_ffmpeg_close_audio_context(&context);
                return status;
            }
        } else {
            av_packet_unref(context.packet);
        }
    }

    int flushStatus = avcodec_send_packet(context.codecContext, NULL);
    if (flushStatus >= 0) {
        status = taption_ffmpeg_receive_audio_frames(
            &context,
            stream,
            callback,
            opaque,
            errorBuffer,
            errorBufferCapacity
        );
    }

    if (result != NULL) {
        *result = context.result;
    }
    int64_t decodedSampleCount = context.decodedSampleCount;
    taption_ffmpeg_close_audio_context(&context);

    if (status != TaptionFFmpegDecodeBridgeStatusOK) {
        return status;
    }
    if (decodedSampleCount <= 0) {
        taption_ffmpeg_set_error(errorBuffer, errorBufferCapacity, "FFmpeg decode bridge did not produce audio samples.");
        return TaptionFFmpegDecodeBridgeStatusNoAudioSamplesDecoded;
    }
    return TaptionFFmpegDecodeBridgeStatusOK;
}

int32_t taption_ffmpeg_decode_bridge_probe_audio_s16(
    const char *sourcePath,
    TaptionFFmpegDecodeBridgeAudioProbeResult *result,
    char *errorBuffer,
    int32_t errorBufferCapacity
) {
    TaptionFFmpegDecodeBridgeAudioContext context;
    int32_t status = taption_ffmpeg_open_audio_context(sourcePath, &context, errorBuffer, errorBufferCapacity);
    if (status != TaptionFFmpegDecodeBridgeStatusOK) {
        taption_ffmpeg_close_audio_context(&context);
        return status;
    }
    if (result != NULL) {
        *result = context.result;
    }
    taption_ffmpeg_close_audio_context(&context);
    return TaptionFFmpegDecodeBridgeStatusOK;
}
