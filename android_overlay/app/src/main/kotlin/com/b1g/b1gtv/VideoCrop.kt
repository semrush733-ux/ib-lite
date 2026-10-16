package com.b1g.b1gtv

import android.content.Context
import android.media.MediaFormat
import android.os.Build
import android.os.Handler
import androidx.media3.common.Format
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.Renderer
import androidx.media3.exoplayer.mediacodec.MediaCodecAdapter
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import androidx.media3.exoplayer.video.MediaCodecVideoRenderer
import androidx.media3.exoplayer.video.VideoRendererEventListener

/**
 * Video chips that hand their pictures over inside a bigger frame.
 *
 * Some video chips (MediaTek, as in Amazon's Fire TV Stick 4K / 4K Max on Fire OS 8) put every
 * picture into a frame larger than the picture and say which part of the frame is the picture
 * (the "crop"). Flutter's video texture on Android 10 and newer (an ImageReader) shows the whole
 * frame and ignores the crop: the picture sits small in the top-left corner and the unused part
 * of the frame shows as a green area. A SurfaceTexture applies the crop, so on such devices the
 * picture goes through one.
 *
 * Which devices: Amazon's on Fire OS 8 and newer, and any other device as soon as its chip is
 * seen padding a picture (remembered on the device). Should a SurfaceTexture ever show no
 * picture at all on a device, the device goes back to the standard texture (also remembered).
 */
@androidx.annotation.OptIn(markerClass = [UnstableApi::class])
object VideoCrop {
    private const val PREFS = "b1g_video"
    private const val KEY_PADS = "chip_pads_pictures"
    private const val KEY_BLANK = "surface_texture_blank"

    @Volatile private var pads: Boolean? = null
    @Volatile private var blank: Boolean? = null
    @Volatile private var blankCount = 0

    /** Whether the app is on screen (kept by MainActivity). */
    @Volatile var foreground = true

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun read(context: Context, key: String): Boolean =
        try { prefs(context).getBoolean(key, false) } catch (_: Exception) { false }

    private fun write(context: Context, key: String, value: Boolean) {
        try { prefs(context).edit().putBoolean(key, value).apply() } catch (_: Exception) {}
    }

    private fun isBlank(context: Context): Boolean = blank ?: read(context, KEY_BLANK).also { blank = it }

    /** Whether pictures must go through a SurfaceTexture on this device. */
    fun needed(context: Context): Boolean {
        // Below Android 10 Flutter's own texture is a SurfaceTexture already.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
        if (isBlank(context)) return false
        if (Build.MANUFACTURER.equals("Amazon", ignoreCase = true)) return true
        return pads ?: read(context, KEY_PADS).also { pads = it }
    }

    /** Whether a session may move to a SurfaceTexture after seeing a padded picture. */
    fun mayUse(context: Context): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && !isBlank(context)

    /** The chip was seen padding a picture: every later video goes through a SurfaceTexture. */
    fun learnPads(context: Context) {
        if (pads != true) {
            pads = true
            write(context, KEY_PADS, true)
        }
        useSurfaceTexturesInFlutter(true)
    }

    /**
     * A SurfaceTexture got pictures but the screen never showed one. Once could be bad luck
     * (the app was just leaving); twice and this device keeps the standard texture.
     */
    fun surfaceTextureShowedNothing(context: Context) {
        blankCount++
        if (blankCount >= 2) {
            blank = true
            write(context, KEY_BLANK, true)
            useSurfaceTexturesInFlutter(false)
        }
    }

    /**
     * MPV (media_kit) asks Flutter for its own texture: Flutter is told to make SurfaceTexture
     * ones, so MPV's direct picture mode is cropped right as well. This is a Flutter switch read
     * through reflection: should a later Flutter drop it, nothing breaks, MPV keeps the old way.
     */
    fun useSurfaceTexturesInFlutter(on: Boolean) {
        try {
            Class.forName("io.flutter.embedding.engine.renderer.FlutterRenderer")
                .getField("debugForceSurfaceProducerGlTextures")
                .setBoolean(null, on)
        } catch (_: Throwable) {
        }
    }

    /**
     * Whether a decoder's output format says the picture is only part of a bigger frame: more
     * than the usual few lines of alignment, or not starting in the top-left corner.
     */
    fun padded(mf: MediaFormat): Boolean {
        for (k in arrayOf("crop-left", "crop-top", "crop-right", "crop-bottom", MediaFormat.KEY_WIDTH, MediaFormat.KEY_HEIGHT)) {
            if (!mf.containsKey(k)) return false
        }
        val left = mf.getInteger("crop-left")
        val top = mf.getInteger("crop-top")
        val w = mf.getInteger("crop-right") - left + 1
        val h = mf.getInteger("crop-bottom") - top + 1
        if (w <= 0 || h <= 0) return false
        return left > 0 || top > 0 ||
            mf.getInteger(MediaFormat.KEY_WIDTH) - w > 16 || mf.getInteger(MediaFormat.KEY_HEIGHT) - h > 16
    }

    /** "1280x720 picture in a 1920x1088 frame", for the log. */
    fun describe(mf: MediaFormat): String = try {
        val w = mf.getInteger("crop-right") - mf.getInteger("crop-left") + 1
        val h = mf.getInteger("crop-bottom") - mf.getInteger("crop-top") + 1
        "${w}x$h picture in a ${mf.getInteger(MediaFormat.KEY_WIDTH)}x${mf.getInteger(MediaFormat.KEY_HEIGHT)} frame"
    } catch (_: Exception) {
        "picture in a bigger frame"
    }
}

/** ExoPlayer's standard video renderer that also says when the chip pads its pictures. */
@androidx.annotation.OptIn(markerClass = [UnstableApi::class])
class CropWatchingVideoRenderer(
    context: Context,
    codecAdapterFactory: MediaCodecAdapter.Factory,
    mediaCodecSelector: MediaCodecSelector,
    allowedJoiningTimeMs: Long,
    enableDecoderFallback: Boolean,
    eventHandler: Handler?,
    eventListener: VideoRendererEventListener?,
    maxDroppedFramesToNotify: Int,
    private val onPadded: (MediaFormat) -> Unit,
) : MediaCodecVideoRenderer(
    context,
    codecAdapterFactory,
    mediaCodecSelector,
    allowedJoiningTimeMs,
    enableDecoderFallback,
    eventHandler,
    eventListener,
    maxDroppedFramesToNotify,
) {
    override fun onOutputFormatChanged(format: Format, mediaFormat: MediaFormat?) {
        super.onOutputFormatChanged(format, mediaFormat)
        try {
            if (mediaFormat != null && VideoCrop.padded(mediaFormat)) onPadded(mediaFormat)
        } catch (_: Exception) {
        }
    }
}

/** ExoPlayer's renderers with [CropWatchingVideoRenderer] in place of the standard video one. */
@androidx.annotation.OptIn(markerClass = [UnstableApi::class])
class CropWatchingRenderersFactory(
    context: Context,
    private val onPadded: (MediaFormat) -> Unit,
) : DefaultRenderersFactory(context) {
    override fun buildVideoRenderers(
        context: Context,
        extensionRendererMode: Int,
        mediaCodecSelector: MediaCodecSelector,
        enableDecoderFallback: Boolean,
        eventHandler: Handler,
        eventListener: VideoRendererEventListener,
        allowedVideoJoiningTimeMs: Long,
        out: ArrayList<Renderer>,
    ) {
        super.buildVideoRenderers(
            context, extensionRendererMode, mediaCodecSelector, enableDecoderFallback,
            eventHandler, eventListener, allowedVideoJoiningTimeMs, out,
        )
        val i = out.indexOfFirst { it.javaClass == MediaCodecVideoRenderer::class.java }
        if (i >= 0) {
            out[i] = CropWatchingVideoRenderer(
                context,
                getCodecAdapterFactory(),
                mediaCodecSelector,
                allowedVideoJoiningTimeMs,
                enableDecoderFallback,
                eventHandler,
                eventListener,
                DefaultRenderersFactory.MAX_DROPPED_VIDEO_FRAME_COUNT_TO_NOTIFY,
                onPadded,
            )
        }
    }
}
