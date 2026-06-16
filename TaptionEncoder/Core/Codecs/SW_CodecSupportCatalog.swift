import Foundation

struct TaptionSoftwareFixtureTarget: Codable, Equatable, Identifiable {
    var id: String { name }
    var name: String
    var videoCodec: TaptionVideoCodec
    var audioCodec: TaptionAudioCodec
    var container: TaptionVideoContainer
    var sourceFamily: String
    var generationStatus: GenerationStatus

    enum GenerationStatus: String, Codable, Equatable {
        case implemented
        case conditionalOnLocalFFmpeg
        case realWorldSampleRequired
        case planned
    }
}

enum SW_CodecSupportCatalog {
    static let softwareVideoDecodeTargets: [TaptionVideoCodec] = [
        .av1,
        .hevc,
        .hevcWithAlpha,
        .dolbyVisionHEVC,
        .h264,
        .vp9,
        .vp8,
        .proRes,
        .proResRaw,
        .theora,
        .mpeg4Visual,
        .mpeg2,
        .mpeg1,
        .h263,
        .motionJPEG,
        .jpeg,
        .jpegXL,
        .animation,
        .cinepak,
        .sorensonVideo,
        .sorensonVideo3,
        .realVideo,
        .roqVideo,
        .dv,
        .dvcPro,
        .dvcProHD,
        .vc1,
        .wmv,
        .ffv1,
        .huffYUV,
        .utVideo,
        .magicYUV,
        .cineForm,
        .dnxhd,
        .pngVideo,
        .rawVideo
    ]

    static let softwareAudioDecodeTargets: [TaptionAudioCodec] = [
        .aac,
        .xheAAC,
        .pcm,
        .alac,
        .opus,
        .mp3,
        .mp2,
        .ac3,
        .eac3,
        .dts,
        .trueHD,
        .flac,
        .vorbis,
        .amr,
        .ilbc,
        .g722,
        .g723,
        .g726,
        .mlp,
        .tta,
        .nellymoser,
        .realAudio,
        .roqDPCM,
        .wavPack,
        .wma,
        .adpcm,
        .aLaw,
        .muLaw
    ]

    static let fixtureTargets: [TaptionSoftwareFixtureTarget] = [
        TaptionSoftwareFixtureTarget(
            name: "av1_mp4_svt_opus",
            videoCodec: .av1,
            audioCodec: .opus,
            container: .mp4,
            sourceFamily: "Web and modern Android",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "av1_webm_svt_opus",
            videoCodec: .av1,
            audioCodec: .opus,
            container: .webm,
            sourceFamily: "Web and browser downloads",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "av1_mkv_svt_opus",
            videoCodec: .av1,
            audioCodec: .opus,
            container: .mkv,
            sourceFamily: "Archive and downloaded video",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "h264_mp4_x264_aac",
            videoCodec: .h264,
            audioCodec: .aac,
            container: .mp4,
            sourceFamily: "iPhone, Android, web",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "h264_mp4_videotoolbox_aac",
            videoCodec: .h264,
            audioCodec: .aac,
            container: .mp4,
            sourceFamily: "Apple hardware encoded H.264",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "h264_mov_x264_pcm",
            videoCodec: .h264,
            audioCodec: .pcm,
            container: .mov,
            sourceFamily: "QuickTime H.264 with PCM",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "h264_m4v_x264_aac",
            videoCodec: .h264,
            audioCodec: .aac,
            container: .m4v,
            sourceFamily: "iTunes-style H.264 video",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "h264_mkv_x264_flac",
            videoCodec: .h264,
            audioCodec: .flac,
            container: .mkv,
            sourceFamily: "Archive H.264 with FLAC",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "h264_mkv_x264_vorbis",
            videoCodec: .h264,
            audioCodec: .vorbis,
            container: .mkv,
            sourceFamily: "Archive H.264 with Vorbis",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "h264_mp4_x264_ac3",
            videoCodec: .h264,
            audioCodec: .ac3,
            container: .mp4,
            sourceFamily: "H.264 with Dolby Digital",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "h264_mp4_x264_eac3",
            videoCodec: .h264,
            audioCodec: .eac3,
            container: .mp4,
            sourceFamily: "H.264 with Dolby Digital Plus",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "h264_ts_x264_aac",
            videoCodec: .h264,
            audioCodec: .aac,
            container: .mpegTransportStream,
            sourceFamily: "Broadcast and camera transport streams",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "h264_tp_x264_aac",
            videoCodec: .h264,
            audioCodec: .aac,
            container: .mpegTransportStream,
            sourceFamily: "Legacy transport stream alias",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "h264_trp_x264_aac",
            videoCodec: .h264,
            audioCodec: .aac,
            container: .mpegTransportStream,
            sourceFamily: "DVR and broadcast transport stream alias",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "h264_tod_x264_aac",
            videoCodec: .h264,
            audioCodec: .aac,
            container: .mpegTransportStream,
            sourceFamily: "JVC-style TOD transport stream alias",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "h264_m2ts_x264_aac",
            videoCodec: .h264,
            audioCodec: .aac,
            container: .mpegTransportStream,
            sourceFamily: "Blu-ray and camera M2TS transport stream alias",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "dji_style_lrf_h264_aac",
            videoCodec: .h264,
            audioCodec: .aac,
            container: .lrf,
            sourceFamily: "DJI low-resolution proxy smoke sample",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "hevc_mp4_x265_aac",
            videoCodec: .hevc,
            audioCodec: .aac,
            container: .mp4,
            sourceFamily: "iPhone, iPad, Android",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "hevc_mp4_videotoolbox_aac",
            videoCodec: .hevc,
            audioCodec: .aac,
            container: .mp4,
            sourceFamily: "Apple hardware encoded H.265",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "hevc_mov_x265_alac",
            videoCodec: .hevc,
            audioCodec: .alac,
            container: .mov,
            sourceFamily: "QuickTime H.265 with Apple Lossless",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "h264_qt_x264_pcm",
            videoCodec: .h264,
            audioCodec: .pcm,
            container: .mov,
            sourceFamily: "QuickTime .qt alias",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "hevc_alpha_mov_sample",
            videoCodec: .hevcWithAlpha,
            audioCodec: .aac,
            container: .mov,
            sourceFamily: "QuickTime alpha-channel exports",
            generationStatus: .planned
        ),
        TaptionSoftwareFixtureTarget(
            name: "dolby_vision_hevc_mov_sample",
            videoCodec: .dolbyVisionHEVC,
            audioCodec: .aac,
            container: .mov,
            sourceFamily: "HDR camera and streaming exports",
            generationStatus: .realWorldSampleRequired
        ),
        TaptionSoftwareFixtureTarget(
            name: "vp9_webm_vpx_opus",
            videoCodec: .vp9,
            audioCodec: .opus,
            container: .webm,
            sourceFamily: "Web",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "vp8_webm_vpx_opus",
            videoCodec: .vp8,
            audioCodec: .opus,
            container: .webm,
            sourceFamily: "Legacy web",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "prores_mov_ks_pcm",
            videoCodec: .proRes,
            audioCodec: .pcm,
            container: .mov,
            sourceFamily: "Camera and editor exports",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "prores_mov_ks_alac",
            videoCodec: .proRes,
            audioCodec: .alac,
            container: .mov,
            sourceFamily: "Camera and editor exports with Apple Lossless",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "ffv1_mkv_flac",
            videoCodec: .ffv1,
            audioCodec: .flac,
            container: .mkv,
            sourceFamily: "Lossless archival video",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "huffyuv_avi_pcm",
            videoCodec: .huffYUV,
            audioCodec: .pcm,
            container: .avi,
            sourceFamily: "Legacy lossless capture",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "ffvhuff_avi_pcm",
            videoCodec: .huffYUV,
            audioCodec: .pcm,
            container: .avi,
            sourceFamily: "FFmpeg HuffYUV variant",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "utvideo_avi_pcm",
            videoCodec: .utVideo,
            audioCodec: .pcm,
            container: .avi,
            sourceFamily: "Lossless editing intermediate",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "magicyuv_avi_pcm",
            videoCodec: .magicYUV,
            audioCodec: .pcm,
            container: .avi,
            sourceFamily: "Lossless editing intermediate",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "cineform_mov_pcm",
            videoCodec: .cineForm,
            audioCodec: .pcm,
            container: .mov,
            sourceFamily: "GoPro CineForm intermediate",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "dnxhr_mov_pcm",
            videoCodec: .dnxhd,
            audioCodec: .pcm,
            container: .mov,
            sourceFamily: "Avid DNxHD/DNxHR intermediate",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "png_mov_pcm",
            videoCodec: .pngVideo,
            audioCodec: .pcm,
            container: .mov,
            sourceFamily: "Lossless frame-based QuickTime video",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "prores_raw_mov_camera_sample",
            videoCodec: .proResRaw,
            audioCodec: .pcm,
            container: .mov,
            sourceFamily: "Pro camera RAW capture",
            generationStatus: .realWorldSampleRequired
        ),
        TaptionSoftwareFixtureTarget(
            name: "mpeg1_mpg_mp2",
            videoCodec: .mpeg1,
            audioCodec: .mp2,
            container: .mpegProgramStream,
            sourceFamily: "Legacy MPEG program streams",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "mpeg1_dat_mp2",
            videoCodec: .mpeg1,
            audioCodec: .mp2,
            container: .mpegProgramStream,
            sourceFamily: "VCD-style DAT program stream alias",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "mpeg2_mpg_mp2",
            videoCodec: .mpeg2,
            audioCodec: .mp2,
            container: .mpegProgramStream,
            sourceFamily: "DVD and broadcast archives",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "mpeg2_mod_mp2",
            videoCodec: .mpeg2,
            audioCodec: .mp2,
            container: .mpegProgramStream,
            sourceFamily: "JVC-style MOD program stream alias",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "mpeg2_vob_mp2",
            videoCodec: .mpeg2,
            audioCodec: .mp2,
            container: .mpegProgramStream,
            sourceFamily: "DVD VOB program stream alias",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "mpeg2_mxf_pcm",
            videoCodec: .mpeg2,
            audioCodec: .pcm,
            container: .mxf,
            sourceFamily: "Broadcast MXF exports",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "mpeg4_avi_mp3",
            videoCodec: .mpeg4Visual,
            audioCodec: .mp3,
            container: .avi,
            sourceFamily: "Legacy phones and cameras",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "mpeg4_divx_mp3",
            videoCodec: .mpeg4Visual,
            audioCodec: .mp3,
            container: .avi,
            sourceFamily: "DivX-style AVI alias",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "h264_flv_x264_aac",
            videoCodec: .h264,
            audioCodec: .aac,
            container: .flv,
            sourceFamily: "Legacy Flash video",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "h264_f4v_x264_aac",
            videoCodec: .h264,
            audioCodec: .aac,
            container: .flv,
            sourceFamily: "Flash video .f4v alias",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "h263_3gp_aac",
            videoCodec: .h263,
            audioCodec: .aac,
            container: .threeGP,
            sourceFamily: "Legacy mobile video",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "h263_3g2_aac",
            videoCodec: .h263,
            audioCodec: .aac,
            container: .threeGPP2,
            sourceFamily: "Legacy 3GPP2 mobile video",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "mjpeg_avi_pcm",
            videoCodec: .motionJPEG,
            audioCodec: .pcm,
            container: .avi,
            sourceFamily: "Legacy camera Motion JPEG",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "jpeg_still_sequence_sample",
            videoCodec: .jpeg,
            audioCodec: .unknown,
            container: .rawElementaryStream,
            sourceFamily: "Still-image and frame-sequence imports",
            generationStatus: .planned
        ),
        TaptionSoftwareFixtureTarget(
            name: "jpegxl_still_sequence_sample",
            videoCodec: .jpegXL,
            audioCodec: .unknown,
            container: .rawElementaryStream,
            sourceFamily: "Modern still-image and frame-sequence imports",
            generationStatus: .planned
        ),
        TaptionSoftwareFixtureTarget(
            name: "qtrle_mov_pcm",
            videoCodec: .animation,
            audioCodec: .pcm,
            container: .mov,
            sourceFamily: "Legacy QuickTime Animation",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "cinepak_mov_pcm",
            videoCodec: .cinepak,
            audioCodec: .pcm,
            container: .mov,
            sourceFamily: "Legacy QuickTime Cinepak",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "sorenson_video_mov_sample",
            videoCodec: .sorensonVideo,
            audioCodec: .pcm,
            container: .mov,
            sourceFamily: "Legacy QuickTime Sorenson Video",
            generationStatus: .conditionalOnLocalFFmpeg
        ),
        TaptionSoftwareFixtureTarget(
            name: "sorenson_video3_mov_sample",
            videoCodec: .sorensonVideo3,
            audioCodec: .pcm,
            container: .mov,
            sourceFamily: "Legacy QuickTime Sorenson Video 3",
            generationStatus: .realWorldSampleRequired
        ),
        TaptionSoftwareFixtureTarget(
            name: "wmv2_asf_wmav2",
            videoCodec: .wmv,
            audioCodec: .wma,
            container: .wmv,
            sourceFamily: "Windows Media",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "wmv2_asf_wmav2_container",
            videoCodec: .wmv,
            audioCodec: .wma,
            container: .asf,
            sourceFamily: "ASF Windows Media container",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "wmv2_dvrms_wmav2",
            videoCodec: .wmv,
            audioCodec: .wma,
            container: .asf,
            sourceFamily: "DVR-MS Windows Media alias",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "h264_raw_elementary",
            videoCodec: .h264,
            audioCodec: .unknown,
            container: .rawElementaryStream,
            sourceFamily: "Raw elementary stream",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "av1_obu_elementary",
            videoCodec: .av1,
            audioCodec: .unknown,
            container: .rawElementaryStream,
            sourceFamily: "Raw AV1 OBU elementary stream alias",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "h263_raw_elementary",
            videoCodec: .h263,
            audioCodec: .unknown,
            container: .rawElementaryStream,
            sourceFamily: "Raw H.263 elementary stream alias",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "mpeg1_raw_m1v",
            videoCodec: .mpeg1,
            audioCodec: .unknown,
            container: .rawElementaryStream,
            sourceFamily: "Raw MPEG-1 elementary stream alias",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "mpeg2_raw_m2v",
            videoCodec: .mpeg2,
            audioCodec: .unknown,
            container: .rawElementaryStream,
            sourceFamily: "Raw MPEG-2 elementary stream alias",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "vp8_ogm_vorbis",
            videoCodec: .vp8,
            audioCodec: .vorbis,
            container: .ogg,
            sourceFamily: "OGM/Ogg media alias",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "vc1_raw_elementary",
            videoCodec: .vc1,
            audioCodec: .unknown,
            container: .rawElementaryStream,
            sourceFamily: "Raw VC-1 elementary stream",
            generationStatus: .realWorldSampleRequired
        ),
        TaptionSoftwareFixtureTarget(
            name: "dv_ntsc_dv",
            videoCodec: .dv,
            audioCodec: .pcm,
            container: .dv,
            sourceFamily: "Tape capture",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "dvcpro_dv_sample",
            videoCodec: .dvcPro,
            audioCodec: .pcm,
            container: .dv,
            sourceFamily: "DVCPro tape capture",
            generationStatus: .planned
        ),
        TaptionSoftwareFixtureTarget(
            name: "dvcprohd_mxf_sample",
            videoCodec: .dvcProHD,
            audioCodec: .pcm,
            container: .mxf,
            sourceFamily: "DVCPro HD broadcast exports",
            generationStatus: .planned
        ),
        TaptionSoftwareFixtureTarget(
            name: "theora_ogv_vorbis",
            videoCodec: .theora,
            audioCodec: .vorbis,
            container: .ogg,
            sourceFamily: "Open web archives",
            generationStatus: .conditionalOnLocalFFmpeg
        ),
        TaptionSoftwareFixtureTarget(
            name: "realvideo_rm_rv20_ac3",
            videoCodec: .realVideo,
            audioCodec: .ac3,
            container: .realMedia,
            sourceFamily: "Legacy RealMedia video",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "roq_video_game",
            videoCodec: .roqVideo,
            audioCodec: .unknown,
            container: .roq,
            sourceFamily: "Legacy game cinematic",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "dji_lrf_camera_sample",
            videoCodec: .h264,
            audioCodec: .aac,
            container: .lrf,
            sourceFamily: "DJI low-resolution proxy",
            generationStatus: .realWorldSampleRequired
        ),
        TaptionSoftwareFixtureTarget(
            name: "rawvideo_yuv_elementary",
            videoCodec: .rawVideo,
            audioCodec: .unknown,
            container: .rawElementaryStream,
            sourceFamily: "Uncompressed raw video frame streams",
            generationStatus: .implemented
        ),
        TaptionSoftwareFixtureTarget(
            name: "h264_nut_x264_pcm",
            videoCodec: .h264,
            audioCodec: .pcm,
            container: .nut,
            sourceFamily: "FFmpeg NUT container archive",
            generationStatus: .implemented
        )
    ]

    static func softwareFallbackPreferred(for codec: TaptionVideoCodec) -> Bool {
        softwareVideoDecodeTargets.contains(codec)
    }
}
