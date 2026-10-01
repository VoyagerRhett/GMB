package com.crcfrcn.citizenapp

import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import io.flutter.plugin.common.MethodCall
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** 广场媒体原生契约的 Android 设备级测试；不读写相册、账户或远端存储。 */
@RunWith(AndroidJUnit4::class)
class SquareMediaChannelInstrumentedTest {
    @Test
    fun requestAcceptsOnlyThePublishedCodecEnvelope() {
        val request = SquareVideoRequest.from(MethodCall("transcode_video", validArguments()))
        assertEquals(854, request.maxWidth)
        assertEquals(48_000, request.audioSampleRate)
        assertEquals(2, request.keyFrameIntervalSeconds)

        val invalid = validArguments().toMutableMap().apply { this["audio_sample_rate"] = 44_100 }
        assertThrows(IllegalArgumentException::class.java) {
            SquareVideoRequest.from(MethodCall("transcode_video", invalid))
        }
    }

    @Test
    fun capabilitiesAlwaysReportBothFailClosedFlags() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val capabilities = SquareVideoTranscoder(context).capabilities()
        assertEquals(setOf("can_encode_hevc", "can_decode_hevc"), capabilities.keys)
        assertEquals(2, capabilities.values.size)
    }

    @Test
    fun fastStartMovesMoovAndPatchesChunkOffset() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val file = File(context.cacheDir, "square-faststart-test.mp4")
        file.delete()
        val ftyp = atom("ftyp", byteArrayOf())
        val mdat = atom("mdat", byteArrayOf(1, 2, 3, 4))
        val oldChunkOffset = ftyp.size + 8
        val stcoPayload = ByteBuffer.allocate(12).order(ByteOrder.BIG_ENDIAN)
            .putInt(0)
            .putInt(1)
            .putInt(oldChunkOffset)
            .array()
        val stbl = atom("stbl", atom("stco", stcoPayload))
        val minf = atom("minf", stbl)
        val mdia = atom("mdia", minf)
        val trak = atom("trak", mdia)
        val moov = atom("moov", trak)
        file.writeBytes(ftyp + mdat + moov)
        assertFalse(SquareMp4FastStart.isFastStart(file))

        SquareMp4FastStart.optimize(file)

        assertTrue(SquareMp4FastStart.isFastStart(file))
        val bytes = file.readBytes()
        val stcoIndex = bytes.indexOfSlice("stco".toByteArray())
        val patchedOffset = ByteBuffer.wrap(bytes, stcoIndex + 12, 4)
            .order(ByteOrder.BIG_ENDIAN)
            .int
        assertEquals(oldChunkOffset + moov.size, patchedOffset)
        file.delete()
    }

    private fun validArguments(): Map<String, Any> = mapOf(
        "input_path" to "/tmp/input.mov",
        "output_path" to "/tmp/output.mp4",
        "cover_path" to "/tmp/cover.png",
        "max_width" to 854,
        "max_height" to 480,
        "video_bitrate" to 504_000,
        "total_peak_bitrate" to 900_000,
        "audio_bitrate" to 96_000,
        "audio_sample_rate" to 48_000,
        "max_frame_rate" to 30,
        "key_frame_interval_seconds" to 2,
        "max_duration_seconds" to 180,
        "max_bytes" to 16_000_000L,
        "cover_max_edge" to 720,
        "cover_quality" to 75,
        "cover_max_bytes" to 512_000,
    )

    private fun atom(type: String, payload: ByteArray): ByteArray = ByteArrayOutputStream().use { output ->
        output.write(ByteBuffer.allocate(4).order(ByteOrder.BIG_ENDIAN).putInt(payload.size + 8).array())
        output.write(type.toByteArray())
        output.write(payload)
        output.toByteArray()
    }

    private fun ByteArray.indexOfSlice(needle: ByteArray): Int {
        for (index in 0..size - needle.size) {
            if (needle.indices.all { this[index + it] == needle[it] }) return index
        }
        error("未找到目标字节序列")
    }
}
