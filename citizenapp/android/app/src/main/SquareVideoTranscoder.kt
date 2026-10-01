package com.crcfrcn.citizenapp

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.annotation.OptIn
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.audio.SonicAudioProcessor
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.Presentation
import androidx.media3.transformer.AudioEncoderSettings
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.EncoderSelector
import androidx.media3.transformer.EncoderUtil
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.InAppMp4Muxer
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.VideoEncoderSettings
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/** Android 广场硬件 HEVC 转码器；API 29 以下统一失败关闭。 */
@OptIn(UnstableApi::class)
class SquareVideoTranscoder(private val context: Context) {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var activeTransformer: Transformer? = null
    private var activeResult: MethodChannel.Result? = null

    fun capabilities(): Map<String, Boolean> = mapOf(
        "can_encode_hevc" to hasHardwareCodec(encoder = true),
        "can_decode_hevc" to hasHardwareCodec(encoder = false),
    )

    fun cancel() {
        mainHandler.post {
            activeTransformer?.cancel()
            activeTransformer = null
            activeResult?.error("square_media_cancelled", "视频处理已取消", null)
            activeResult = null
        }
    }

    fun transcode(request: SquareVideoRequest, result: MethodChannel.Result) {
        check(Looper.myLooper() == Looper.getMainLooper()) { "视频转码必须从主线程启动" }
        check(activeTransformer == null) { "已有视频正在处理" }
        require(hasHardwareCodec(encoder = true) && hasHardwareCodec(encoder = false)) {
            "当前设备不具备硬件 HEVC 编解码能力"
        }
        val input = File(request.inputPath)
        val output = File(request.outputPath)
        val cover = File(request.coverPath)
        require(input.isFile && input.length() > 0) { "输入视频不存在" }
        require(output.canonicalPath != input.canonicalPath) { "禁止覆盖原始视频" }
        output.parentFile?.mkdirs()
        cover.parentFile?.mkdirs()
        output.delete()
        cover.delete()

        val source = inspectSource(input)
        require(source.durationSeconds in 1..request.maxDurationSeconds) { "视频时长超出会员上限" }
        require(!source.isHdr) { "HDR/Dolby Vision 视频不允许发布，请先转为 SDR" }
        val target = fitVideo(source.width, source.height, request.maxWidth, request.maxHeight)
        val videoEffect: Effect = Presentation.createForWidthAndHeight(
            target.first,
            target.second,
            Presentation.LAYOUT_SCALE_TO_FIT,
        )
        val resampler = SonicAudioProcessor().apply {
            setOutputSampleRateHz(request.audioSampleRate)
        }
        val editedMediaItem = EditedMediaItem.Builder(MediaItem.fromUri(input.toURI().toString()))
            .setFrameRate(min(source.frameRate.roundToInt().coerceAtLeast(1), request.maxFrameRate))
            .setEffects(Effects(listOf(resampler), listOf(videoEffect)))
            .build()

        val videoSettings = VideoEncoderSettings.Builder()
            .setBitrate(request.videoBitrate)
            .setBitrateMode(MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_VBR)
            .setiFrameIntervalSeconds(request.keyFrameIntervalSeconds.toFloat())
            .setMaxBFrames(0)
            .build()
        val audioSettings = AudioEncoderSettings.Builder()
            .setBitrate(request.audioBitrate)
            .setProfile(MediaCodecInfo.CodecProfileLevel.AACObjectLC)
            .build()
        val encoderFactory = DefaultEncoderFactory.Builder(context)
            .setEnableFallback(false)
            .setVideoEncoderSelector(EncoderSelector.DEFAULT)
            .setRequestedVideoEncoderSettings(videoSettings)
            .setRequestedAudioEncoderSettings(audioSettings)
            .build()

        val completed = AtomicBoolean(false)
        val listener = object : Transformer.Listener {
            override fun onCompleted(composition: androidx.media3.transformer.Composition, exportResult: ExportResult) {
                if (!completed.compareAndSet(false, true)) return
                activeTransformer = null
                activeResult = null
                try {
                    SquareMp4FastStart.optimize(output)
                    createCover(output, cover, request)
                    val inspected = inspectOutput(output, cover, request)
                    result.success(inspected)
                } catch (error: Exception) {
                    output.delete()
                    cover.delete()
                    result.error("square_media_verify_failed", error.message, null)
                }
            }

            override fun onError(
                composition: androidx.media3.transformer.Composition,
                exportResult: ExportResult,
                exportException: ExportException,
            ) {
                if (!completed.compareAndSet(false, true)) return
                activeTransformer = null
                activeResult = null
                output.delete()
                cover.delete()
                result.error("square_media_transcode_failed", exportException.message, null)
            }
        }
        val transformer = Transformer.Builder(context)
            .setVideoMimeType(MimeTypes.VIDEO_H265)
            .setAudioMimeType(MimeTypes.AUDIO_AAC)
            .setEncoderFactory(encoderFactory)
            .setMuxerFactory(InAppMp4Muxer.Factory())
            .addListener(listener)
            .build()
        activeTransformer = transformer
        activeResult = result
        transformer.start(editedMediaItem, output.absolutePath)
        pollProgress(transformer, completed)
    }

    private fun pollProgress(transformer: Transformer, completed: AtomicBoolean) {
        if (completed.get() || activeTransformer !== transformer) return
        // 保持调用 Transformer#getProgress，确保长视频任务的内部状态持续可观测；
        // Flutter 当前只展示“处理媒体”阶段，第三步上传协议不依赖该瞬时百分比。
        transformer.getProgress(ProgressHolder())
        mainHandler.postDelayed({ pollProgress(transformer, completed) }, 500)
    }

    private fun hasHardwareCodec(encoder: Boolean): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
        return if (encoder) {
            EncoderUtil.getSupportedEncoders(MimeTypes.VIDEO_H265)
                .any { EncoderUtil.isHardwareAccelerated(it, MimeTypes.VIDEO_H265) }
        } else {
            android.media.MediaCodecList(android.media.MediaCodecList.REGULAR_CODECS).codecInfos.any { info ->
                !info.isEncoder && info.isHardwareAccelerated &&
                    info.supportedTypes.any { it.equals(MediaFormat.MIMETYPE_VIDEO_HEVC, ignoreCase = true) }
            }
        }
    }

    private data class SourceInfo(
        val durationSeconds: Int,
        val width: Int,
        val height: Int,
        val frameRate: Float,
        val isHdr: Boolean,
    )

    private fun inspectSource(file: File): SourceInfo {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(file.absolutePath)
            val video = (0 until extractor.trackCount)
                .map(extractor::getTrackFormat)
                .firstOrNull { it.getString(MediaFormat.KEY_MIME)?.startsWith("video/") == true }
                ?: throw IllegalArgumentException("文件不包含视频轨")
            val mime = video.getString(MediaFormat.KEY_MIME)
            require(mime != MediaFormat.MIMETYPE_VIDEO_DOLBY_VISION) { "禁止 Dolby Vision 视频" }
            val transfer = video.intOrNull(MediaFormat.KEY_COLOR_TRANSFER)
            val isHdr = transfer == MediaFormat.COLOR_TRANSFER_HLG ||
                transfer == MediaFormat.COLOR_TRANSFER_ST2084
            val retriever = MediaMetadataRetriever()
            try {
                retriever.setDataSource(file.absolutePath)
                val durationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                    ?.toLongOrNull() ?: 0L
                var width = video.getInteger(MediaFormat.KEY_WIDTH)
                var height = video.getInteger(MediaFormat.KEY_HEIGHT)
                val rotation = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                    ?.toIntOrNull() ?: 0
                if (rotation == 90 || rotation == 270) {
                    width = height.also { height = width }
                }
                val frameRate = video.floatOrNull(MediaFormat.KEY_FRAME_RATE) ?: 30f
                return SourceInfo(ceil(durationMs / 1000.0).toInt(), width, height, frameRate, isHdr)
            } finally {
                retriever.release()
            }
        } finally {
            extractor.release()
        }
    }

    private fun fitVideo(width: Int, height: Int, maxWidth: Int, maxHeight: Int): Pair<Int, Int> {
        val boundWidth = if (height > width) maxHeight else maxWidth
        val boundHeight = if (height > width) maxWidth else maxHeight
        val scale = min(1.0, min(boundWidth.toDouble() / width, boundHeight.toDouble() / height))
        val outputWidth = max(2, ((width * scale).roundToInt() / 2) * 2)
        val outputHeight = max(2, ((height * scale).roundToInt() / 2) * 2)
        return outputWidth to outputHeight
    }

    private fun createCover(video: File, cover: File, request: SquareVideoRequest) {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(video.absolutePath)
            val frame = retriever.getFrameAtTime(1_000_000L, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                ?: retriever.getFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                ?: throw IllegalArgumentException("无法生成视频封面")
            val longest = max(frame.width, frame.height)
            val scale = min(1.0, request.coverMaxEdge.toDouble() / longest)
            val scaled = if (scale < 1.0) {
                Bitmap.createScaledBitmap(
                    frame,
                    max(2, (frame.width * scale).roundToInt()),
                    max(2, (frame.height * scale).roundToInt()),
                    true,
                ).also { frame.recycle() }
            } else frame
            try {
                FileOutputStream(cover, false).use { output ->
                    require(scaled.compress(Bitmap.CompressFormat.PNG, 100, output)) {
                        "视频封面 PNG 编码失败"
                    }
                }
                require(cover.length() > 0) { "视频封面为空" }
            } finally {
                scaled.recycle()
            }
        } finally {
            retriever.release()
        }
    }

    private fun inspectOutput(video: File, cover: File, request: SquareVideoRequest): Map<String, Any> {
        require(video.length() in 1..request.maxBytes) { "视频成品超过大小上限" }
        require(SquareMp4FastStart.isFastStart(video)) { "视频成品不是 faststart MP4" }
        require(SquareMp4FastStart.containsSampleEntry(video, "hvc1")) { "视频 sample entry 不是 hvc1" }
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(video.absolutePath)
            var videoFormat: MediaFormat? = null
            var durationUs = 0L
            for (index in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(index)
                val mime = format.getString(MediaFormat.KEY_MIME).orEmpty()
                durationUs = max(durationUs, format.longOrNull(MediaFormat.KEY_DURATION) ?: 0L)
                if (mime.startsWith("video/")) {
                    require(mime == MediaFormat.MIMETYPE_VIDEO_HEVC) { "视频编码不是 HEVC" }
                    videoFormat = format
                } else if (mime.startsWith("audio/")) {
                    require(mime == MediaFormat.MIMETYPE_AUDIO_AAC) { "音频编码不是 AAC-LC" }
                    require(format.getInteger(MediaFormat.KEY_SAMPLE_RATE) == request.audioSampleRate) {
                        "音频采样率不是 48kHz"
                    }
                }
                extractor.selectTrack(index)
            }
            val format = videoFormat ?: throw IllegalArgumentException("成品缺少视频轨")
            require(durationUs > 0) { "视频成品时长不合法" }
            val peak = peakBitrate(extractor)
            val durationSeconds = ceil(durationUs / 1_000_000.0).toInt()
            val average = (video.length() * 8_000_000L / durationUs).toInt()
            val transfer = format.intOrNull(MediaFormat.KEY_COLOR_TRANSFER)
            val isSdr = transfer == null || transfer == MediaFormat.COLOR_TRANSFER_SDR_VIDEO
            return mapOf(
                "duration_seconds" to durationSeconds,
                "width" to format.getInteger(MediaFormat.KEY_WIDTH),
                "height" to format.getInteger(MediaFormat.KEY_HEIGHT),
                "frame_rate" to (format.floatOrNull(MediaFormat.KEY_FRAME_RATE) ?: request.maxFrameRate.toFloat()),
                "total_average_bitrate" to average,
                "total_peak_bitrate" to peak,
                "byte_size" to video.length(),
                "cover_byte_size" to cover.length(),
                "video_codec" to "hevc",
                "sample_entry" to "hvc1",
                "fast_start" to true,
                "is_sdr" to isSdr,
            )
        } finally {
            extractor.release()
        }
    }

    private fun peakBitrate(extractor: MediaExtractor): Int {
        val buckets = mutableMapOf<Long, Long>()
        while (true) {
            val sampleSize = extractor.sampleSize
            val sampleTime = extractor.sampleTime
            if (sampleSize < 0 || sampleTime < 0) break
            val second = sampleTime / 1_000_000L
            buckets[second] = (buckets[second] ?: 0L) + sampleSize * 8L
            if (!extractor.advance()) break
        }
        return (buckets.values.maxOrNull() ?: 0L).coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
    }
}

private fun MediaFormat.intOrNull(key: String): Int? =
    if (containsKey(key)) getInteger(key) else null

private fun MediaFormat.longOrNull(key: String): Long? =
    if (containsKey(key)) getLong(key) else null

private fun MediaFormat.floatOrNull(key: String): Float? =
    if (containsKey(key)) getNumber(key)?.toFloat() else null
