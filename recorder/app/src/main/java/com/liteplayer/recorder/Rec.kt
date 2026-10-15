package com.liteplayer.recorder

import android.content.Context
import android.media.MediaCodecList
import android.media.MediaFormat
import android.media.MediaRecorder
import android.os.Build
import android.view.Surface
import java.io.File

/** Something that turns the screen (sent to [surface]) into an MP4 file. */
interface Rec {
    val surface: Surface
    val width: Int
    val height: Int
    val withSound: Boolean
    val name: String
    /** Pictures written so far (-1 = cannot tell). */
    fun frames(): Int
    fun begin()
    fun stop(): Boolean
    fun abandon()
}

/**
 * Android's own recorder (MediaRecorder): the most widely working path on TV boxes. Picture
 * only (it cannot take the apps' sound). Used when the encoder path gives no picture.
 */
class MediaRec(
    ctx: Context,
    override val width: Int,
    override val height: Int,
    fps: Int,
    bitrate: Int,
    private val out: File,
) : Rec {
    private val mr: MediaRecorder = if (Build.VERSION.SDK_INT >= 31) MediaRecorder(ctx) else @Suppress("DEPRECATION") MediaRecorder()
    private var started = false
    private var startedAt = 0L

    init {
        mr.setVideoSource(MediaRecorder.VideoSource.SURFACE)
        mr.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
        mr.setVideoEncoder(MediaRecorder.VideoEncoder.H264)
        mr.setVideoSize(width, height)
        mr.setVideoFrameRate(fps)
        mr.setVideoEncodingBitRate(bitrate)
        mr.setOutputFile(out.path)
        mr.prepare()
    }

    override val surface: Surface = mr.surface
    override val withSound = false
    override val name = "android recorder"
    override fun frames() = -1

    override fun begin() {
        mr.start()
        started = true
        startedAt = System.currentTimeMillis()
    }

    override fun stop(): Boolean {
        var ok = false
        try {
            if (started) {
                // Stopping within the first second can fail: give it a moment.
                val age = System.currentTimeMillis() - startedAt
                if (age < 1200) Thread.sleep(1200 - age)
                mr.stop()
                ok = out.length() > 0
            }
        } catch (_: Exception) {
            ok = false
        }
        try { mr.reset() } catch (_: Exception) {}
        try { mr.release() } catch (_: Exception) {}
        return ok
    }

    override fun abandon() {
        stop()
        out.delete()
    }
}

object Sizes {
    /**
     * Recording sizes to try, best first: the screen scaled to [want] (even numbers), the same
     * rounded to multiples of 16 (many TV encoders need that), then 720p. Sizes the encoder says
     * it cannot do are left out.
     */
    fun candidates(sw: Int, sh: Int, want: Int): List<Pair<Int, Int>> {
        val out = LinkedHashSet<Pair<Int, Int>>()
        for (q in if (want >= 1080) listOf(1080, 720) else listOf(720)) {
            val shortSide = minOf(sw, sh)
            val k = if (shortSide > q) q.toDouble() / shortSide else 1.0
            val w = (Math.round(sw * k).toInt() / 2) * 2
            val h = (Math.round(sh * k).toInt() / 2) * 2
            out += w to h
            out += (w / 16) * 16 to (h / 16) * 16
        }
        out += 1280 to 720
        val caps = try {
            MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos
                .filter { it.isEncoder && it.supportedTypes.any { t -> t.equals(MediaFormat.MIMETYPE_VIDEO_AVC, true) } }
                .mapNotNull { it.getCapabilitiesForType(MediaFormat.MIMETYPE_VIDEO_AVC).videoCapabilities }
        } catch (_: Exception) {
            emptyList()
        }
        val ok = out.filter { (w, h) -> w > 0 && h > 0 && (caps.isEmpty() || caps.any { c -> c.isSizeSupported(w, h) }) }
        return ok.ifEmpty { listOf(1280 to 720) }
    }
}
