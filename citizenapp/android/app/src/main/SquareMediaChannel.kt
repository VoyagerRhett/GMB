package com.crcfrcn.citizenapp

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** 公民广场媒体原生入口；通道字段统一使用 snake_case。 */
class SquareMediaChannel(
    messenger: BinaryMessenger,
    context: Context,
) {
    private val transcoder = SquareVideoTranscoder(context.applicationContext)
    private val channel = MethodChannel(messenger, CHANNEL_NAME)

    init {
        channel.setMethodCallHandler(::handle)
    }

    fun dispose() {
        transcoder.cancel()
        channel.setMethodCallHandler(null)
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "capabilities" -> result.success(transcoder.capabilities())
            "transcode_video" -> {
                try {
                    transcoder.transcode(SquareVideoRequest.from(call), result)
                } catch (error: Exception) {
                    result.error("square_media_invalid", error.message, null)
                }
            }
            "cancel_video" -> {
                transcoder.cancel()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    companion object {
        const val CHANNEL_NAME = "citizenapp/square_media"
    }
}

data class SquareVideoRequest(
    val inputPath: String,
    val outputPath: String,
    val coverPath: String,
    val maxWidth: Int,
    val maxHeight: Int,
    val videoBitrate: Int,
    val totalPeakBitrate: Int,
    val audioBitrate: Int,
    val audioSampleRate: Int,
    val maxFrameRate: Int,
    val keyFrameIntervalSeconds: Int,
    val maxDurationSeconds: Int,
    val maxBytes: Long,
    val coverMaxEdge: Int,
    val coverQuality: Int,
    val coverMaxBytes: Int,
) {
    init {
        require(inputPath.isNotBlank() && outputPath.isNotBlank() && coverPath.isNotBlank()) {
            "媒体路径不能为空"
        }
        require(maxWidth in 2..1920 && maxHeight in 2..1080) { "视频尺寸不合法" }
        require(videoBitrate > 0 && audioBitrate > 0 && totalPeakBitrate > 0) { "视频码率不合法" }
        require(audioSampleRate == 48_000) { "音频采样率必须为 48kHz" }
        require(maxFrameRate in 1..30 && keyFrameIntervalSeconds == 2) { "帧率或关键帧间隔不合法" }
        require(maxDurationSeconds in 1..10_800 && maxBytes in 1..3_000_000_000L) { "视频上限不合法" }
        require(coverMaxEdge in 2..720 && coverQuality in 1..100 && coverMaxBytes in 1..512_000) {
            "视频封面规则不合法"
        }
    }

    companion object {
        fun from(call: MethodCall): SquareVideoRequest = SquareVideoRequest(
            inputPath = call.requiredString("input_path"),
            outputPath = call.requiredString("output_path"),
            coverPath = call.requiredString("cover_path"),
            maxWidth = call.requiredInt("max_width"),
            maxHeight = call.requiredInt("max_height"),
            videoBitrate = call.requiredInt("video_bitrate"),
            totalPeakBitrate = call.requiredInt("total_peak_bitrate"),
            audioBitrate = call.requiredInt("audio_bitrate"),
            audioSampleRate = call.requiredInt("audio_sample_rate"),
            maxFrameRate = call.requiredInt("max_frame_rate"),
            keyFrameIntervalSeconds = call.requiredInt("key_frame_interval_seconds"),
            maxDurationSeconds = call.requiredInt("max_duration_seconds"),
            maxBytes = call.requiredLong("max_bytes"),
            coverMaxEdge = call.requiredInt("cover_max_edge"),
            coverQuality = call.requiredInt("cover_quality"),
            coverMaxBytes = call.requiredInt("cover_max_bytes"),
        )
    }
}

private fun MethodCall.requiredString(key: String): String =
    argument<String>(key)?.takeIf { it.isNotBlank() }
        ?: throw IllegalArgumentException("$key 缺失")

private fun MethodCall.requiredInt(key: String): Int =
    (argument<Number>(key)?.toInt()) ?: throw IllegalArgumentException("$key 缺失")

private fun MethodCall.requiredLong(key: String): Long =
    (argument<Number>(key)?.toLong()) ?: throw IllegalArgumentException("$key 缺失")
