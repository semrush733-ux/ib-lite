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
    /** Pictures stored in the file so far (-1 = cannot tell). */
    fun written(): Int = -1
    /** What happened inside (for the on-screen reason). */
    fun report(): String = ""
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

/** One way to record: size, pictures a second and video format. */
data class Plan(val w: Int, val h: Int, val fps: Int, val mime: String) {
    val hevc get() = mime == MediaFormat.MIMETYPE_VIDEO_HEVC
    val label: String
        get() = (if (minOf(w, h) >= 2160) "4K" else "${minOf(w, h)}p") + " $fps fps " + (if (hevc) "H.265" else "H.264")
}

object Sizes {
    private fun caps(mime: String) = try {
        MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos
            .filter { it.isEncoder && it.supportedTypes.any { t -> t.equals(mime, true) } }
            .mapNotNull { it.getCapabilitiesForType(mime).videoCapabilities }
    } catch (_: Exception) {
        emptyList()
    }

    /**
     * Ways to record, best first. [sw]x[sh] is what the TV draws its apps at, [pw]x[ph] the
     * panel (4K TVs often draw apps at 1080p but show video at 4K). Only sizes and speeds the
     * TV's encoders say they can do are listed; H.265 is used where H.264 cannot do the size.
     */
    fun plans(sw: Int, sh: Int, pw: Int, ph: Int, want: Int, fps: Int): List<Plan> {
        val heights = when {
            want >= 2160 -> listOf(2160, 1440, 1080, 720)
            want >= 1080 -> listOf(1080, 720)
            else -> listOf(720)
        }
        val dims = LinkedHashSet<Pair<Int, Int>>()
        for (q in heights) {
            val (bw, bh) = if (q > minOf(sw, sh) && minOf(pw, ph) > minOf(sw, sh)) pw to ph else sw to sh
            if (q > minOf(bw, bh)) continue  // the TV shows less than this: no point
            val k = q.toDouble() / minOf(bw, bh)
            val w = (Math.round(bw * k).toInt() / 2) * 2
            val h = (Math.round(bh * k).toInt() / 2) * 2
            dims += w to h
            dims += (w / 16) * 16 to (h / 16) * 16
        }
        if (dims.isEmpty()) dims += ((sw / 2) * 2) to ((sh / 2) * 2)
        dims += 1280 to 720
        val avc = caps(MediaFormat.MIMETYPE_VIDEO_AVC)
        val hevc = caps(MediaFormat.MIMETYPE_VIDEO_HEVC)
        val out = ArrayList<Plan>()
        for ((w, h) in dims) {
            if (w <= 0 || h <= 0) continue
            fun pick(c: List<android.media.MediaCodecInfo.VideoCapabilities>, mime: String): Plan? {
                if (c.isEmpty()) return if (mime == MediaFormat.MIMETYPE_VIDEO_AVC) Plan(w, h, fps, mime) else null
                for (f in listOf(fps, 50, 30).filter { it <= fps }.distinct()) {
                    if (c.any { v -> try { v.areSizeAndRateSupported(w, h, f.toDouble()) } catch (_: Exception) { false } }) return Plan(w, h, f, mime)
                }
                return null
            }
            val a = pick(avc, MediaFormat.MIMETYPE_VIDEO_AVC)
            val b = if (a == null || a.fps < fps) pick(hevc, MediaFormat.MIMETYPE_VIDEO_HEVC) else null
            // Prefer whichever keeps the chosen smoothness; H.264 when equal (plays everywhere).
            when {
                a != null && (b == null || b.fps <= a.fps) -> out += a
                b != null -> { out += b; if (a != null) out += a }
            }
        }
        return out.ifEmpty { listOf(Plan(1280, 720, 30, MediaFormat.MIMETYPE_VIDEO_AVC)) }
    }
}
