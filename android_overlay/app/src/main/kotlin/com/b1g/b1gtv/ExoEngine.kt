package com.b1g.b1gtv

import android.content.Context
import android.media.MediaFormat
import android.os.Handler
import android.os.Looper
import android.view.Surface
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.common.VideoSize
import androidx.media3.common.text.CueGroup
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.Renderer
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

/**
 * ExoPlayer (Media3) as a player engine inside the Flutter screen.
 *
 * The picture is drawn into a Flutter texture, so the app's own controls (channel list, audio,
 * subtitles, quality, EPG...) stay on top of it. Flutter talks to it over the "b1g/exo" channel:
 * create / open / play / pause / seek / rate / track / dispose / facts. Changes come back as
 * "event" calls with the engine id: state (position, duration, buffering, playing), size,
 * tracks, cues (subtitle text), ended, error, texture (the picture moved to another texture)
 * and log.
 *
 * The texture is Flutter's standard one, or a SurfaceTexture on devices whose video chip hands
 * its pictures over inside a bigger frame (see [VideoCrop]): there the standard texture would
 * show the picture small in a corner with a green area around it.
 */
class ExoEngine(
    private val context: Context,
    private val textures: TextureRegistry,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "b1g/exo")
    private val sessions = HashMap<Int, Session>()
    private var nextId = 1
    private val main = Handler(Looper.getMainLooper())

    init {
        channel.setMethodCallHandler(this)
    }

    fun disposeAll() {
        sessions.values.forEach { it.release() }
        sessions.clear()
    }

    private fun send(id: Int, type: String, data: Map<String, Any?> = emptyMap()) {
        val payload = HashMap<String, Any?>(data)
        payload["id"] = id
        payload["type"] = type
        main.post {
            try {
                channel.invokeMethod("event", payload)
            } catch (_: Exception) {
            }
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            if (call.method == "create") {
                val id = nextId++
                val live = call.argument<Boolean>("live") ?: true
                val ua = call.argument<String>("ua") ?: "CloudPlayer/1.0 (Android TV)"
                val startMs = (call.argument<Number>("startMs") ?: 1500).toInt().coerceIn(500, 8000)
                val rebufMs = (call.argument<Number>("rebufMs") ?: 3000).toInt().coerceIn(1000, 15000)
                val s = Session(id, live, ua, startMs, rebufMs)
                sessions[id] = s
                result.success(mapOf("id" to id, "texture" to s.textureId, "cropSafe" to s.onSurfaceTexture))
                return
            }
            val id = (call.argument<Number>("id") ?: 0).toInt()
            val s = sessions[id]
            if (s == null) {
                result.success(null)
                return
            }
            when (call.method) {
                "open" -> s.open(
                    call.argument<String>("url") ?: "",
                    (call.argument<Number>("startMs") ?: 0).toLong(),
                    (call.argument<Number>("enhance") ?: 0).toInt(),
                    call.argument<Boolean>("paused") ?: false,
                )
                "play" -> s.player.play()
                // Lets go of the stream (and the server connection) but keeps the last picture
                // on screen; the same engine opens the next address.
                "stop" -> s.player.stop()
                "pause" -> s.player.pause()
                "seek" -> s.player.seekTo((call.argument<Number>("ms") ?: 0).toLong())
                "rate" -> s.player.playbackParameters = PlaybackParameters((call.argument<Number>("rate") ?: 1.0).toFloat())
                "track" -> s.selectTrack(call.argument<String>("kind") ?: "", call.argument<String>("track") ?: "")
                "facts" -> {
                    result.success(s.facts())
                    return
                }
                "dispose" -> {
                    s.release()
                    sessions.remove(id)
                }
                else -> {
                    result.notImplemented()
                    return
                }
            }
            result.success(null)
        } catch (e: Exception) {
            result.error("exo", e.message, null)
        }
    }

    private inner class Session(
        val id: Int,
        private val live: Boolean,
        ua: String,
        startMs: Int = 1500,
        rebufMs: Int = 3000,
    ) {
        // Where the picture goes: Flutter's standard texture, or a SurfaceTexture (one of the two).
        private var producer: TextureRegistry.SurfaceProducer? = null
        private var stEntry: TextureRegistry.SurfaceTextureEntry? = null
        private var stSurface: Surface? = null
        private val consumed = java.util.concurrent.atomic.AtomicLong(0)
        private var pictureChecked = false
        var textureId: Long = -1L
            private set
        val onSurfaceTexture: Boolean get() = stEntry != null
        val player: ExoPlayer
        private var released = false
        private var tracks: Tracks = Tracks.EMPTY
        private var decoder = ""
        private var dropped = 0
        private var enhance = 0
        private var outW = 1920
        private var outH = 1080
        private val ticker = object : Runnable {
            override fun run() {
                if (released) return
                sendState()
                main.postDelayed(this, 250)
            }
        }

        init {
            val http = DefaultHttpDataSource.Factory()
                .setUserAgent(ua)
                .setAllowCrossProtocolRedirects(true)
                .setConnectTimeoutMs(15000)
                .setReadTimeoutMs(20000)
            // Live: keep up to 30 s, films up to 60 s. How much must be there before the picture
            // starts / restarts comes from the app: little on a server that never stalls (quick
            // start), more on one that often does (fewer stops).
            val minBuf = maxOf(if (live) 10000 else 20000, rebufMs * 2)
            val load = DefaultLoadControl.Builder()
                .setBufferDurationsMs(minBuf, maxOf(if (live) 30000 else 60000, minBuf + 5000), startMs, rebufMs)
                .setPrioritizeTimeOverSizeThresholds(true)
                .build()
            // The standard renderers; the video one also says when the chip pads its pictures.
            val renderers = CropWatchingRenderersFactory(context) { mf -> main.post { onPaddedPictures(mf) } }
                .setEnableDecoderFallback(true)
                .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON)
            player = ExoPlayer.Builder(context, renderers)
                .setMediaSourceFactory(DefaultMediaSourceFactory(DefaultDataSource.Factory(context, http)))
                .setLoadControl(load)
                .build()

            if (VideoCrop.needed(context)) attachSurfaceTexture() else attachProducer()

            player.addListener(object : Player.Listener {
                override fun onPlaybackStateChanged(state: Int) {
                    sendState()
                    if (state == Player.STATE_ENDED) send(id, "ended")
                }

                override fun onIsPlayingChanged(isPlaying: Boolean) = sendState()

                override fun onPlayerError(error: PlaybackException) {
                    // A live stream that fell behind simply restarts at the live edge.
                    if (error.errorCode == PlaybackException.ERROR_CODE_BEHIND_LIVE_WINDOW) {
                        player.seekToDefaultPosition()
                        player.prepare()
                        return
                    }
                    send(id, "error", mapOf("message" to "${error.errorCodeName}: ${error.message ?: ""}"))
                }

                override fun onVideoSizeChanged(size: VideoSize) {
                    if (size.width <= 0 || size.height <= 0) return
                    outW = size.width
                    outH = size.height
                    val p = producer
                    if (p != null) {
                        p.setSize(size.width, size.height)
                        player.setVideoSurface(p.surface)
                    } else {
                        // Same surface; the size counts when the picture is drawn with effects.
                        try {
                            stEntry?.surfaceTexture()?.setDefaultBufferSize(size.width, size.height)
                        } catch (_: Exception) {
                        }
                    }
                    if (enhance > 0) signalOutputSize()
                    send(id, "size", mapOf("w" to size.width, "h" to size.height))
                }

                override fun onTracksChanged(t: Tracks) {
                    tracks = t
                    send(id, "tracks", mapOf("list" to describeTracks(t)))
                    // Sound this device cannot decode (often AC3 / E-AC3 / MP2): the picture
                    // plays but stays silent. Tell the app, which moves the channel to MPV.
                    var audio = 0
                    var playable = 0
                    var mime = ""
                    for (g in t.groups) {
                        if (g.type != C.TRACK_TYPE_AUDIO) continue
                        for (i in 0 until g.length) {
                            audio++
                            if (mime.isEmpty()) mime = g.getTrackFormat(i).sampleMimeType ?: ""
                            if (g.isTrackSupported(i, false)) playable++
                        }
                    }
                    if (audio > 0 && playable == 0) send(id, "noaudio", mapOf("mime" to mime))
                }

                override fun onRenderedFirstFrame() {
                    send(id, "firstframe")
                    watchSurfaceTexture()
                }

                override fun onCues(cueGroup: CueGroup) {
                    val text = cueGroup.cues.mapNotNull { it.text?.toString() }.joinToString("\n")
                    send(id, "cues", mapOf("text" to text))
                }
            })
            player.addAnalyticsListener(object : AnalyticsListener {
                override fun onVideoDecoderInitialized(
                    eventTime: AnalyticsListener.EventTime,
                    decoderName: String,
                    initializedTimestampMs: Long,
                    initializationDurationMs: Long,
                ) {
                    decoder = decoderName
                }

                override fun onDroppedVideoFrames(eventTime: AnalyticsListener.EventTime, droppedFrames: Int, elapsedMs: Long) {
                    dropped += droppedFrames
                }
            })
            main.post(ticker)
        }

        /** Flutter's standard texture (an ImageReader on Android 10 and newer). */
        private fun attachProducer() {
            val p = textures.createSurfaceProducer()
            producer = p
            textureId = p.id()
            p.setSize(outW, outH)
            p.setCallback(object : TextureRegistry.SurfaceProducer.Callback {
                override fun onSurfaceAvailable() {
                    if (!released && producer === p) player.setVideoSurface(p.surface)
                }

                override fun onSurfaceCleanup() {
                    if (!released && producer === p) player.setVideoSurface(null)
                }
            })
            player.setVideoSurface(p.surface)
        }

        /** A SurfaceTexture: Flutter shows only the part of the frame that is the picture. */
        private fun attachSurfaceTexture() {
            val e = textures.createSurfaceTexture()
            e.surfaceTexture().setDefaultBufferSize(outW, outH)
            e.setOnFrameConsumedListener { consumed.incrementAndGet() }
            val s = Surface(e.surfaceTexture())
            stEntry = e
            stSurface = s
            textureId = e.id()
            player.setVideoSurface(s)
        }

        /** The video chip padded a picture: from now on it goes through a SurfaceTexture. */
        private fun onPaddedPictures(mf: MediaFormat) {
            if (released || !VideoCrop.mayUse(context)) return
            VideoCrop.learnPads(context)
            val old = producer ?: return // already on a SurfaceTexture
            producer = null
            attachSurfaceTexture()
            send(id, "texture", mapOf("texture" to textureId))
            send(id, "log", mapOf("text" to "the video chip pads its pictures (${VideoCrop.describe(mf)}): picture moved to a SurfaceTexture"))
            // Flutter switches to the new texture on its next frame; the old one goes after that.
            main.postDelayed({
                try {
                    old.release()
                } catch (_: Exception) {
                }
            }, 1500)
        }

        /** Pictures this player has handed to the screen so far. */
        private fun renderedCount(): Long = try {
            val c = player.videoDecoderCounters
            c?.ensureUpdated()
            c?.renderedOutputBufferCount?.toLong() ?: 0L
        } catch (_: Exception) {
            0L
        }

        /**
         * Safety net for the SurfaceTexture: a few seconds after the first picture, the screen must
         * have taken pictures from it. If it took none while the video played, this session goes
         * back to the standard texture (a picture with a green area is better than none).
         */
        private fun watchSurfaceTexture() {
            if (pictureChecked || stEntry == null) return
            pictureChecked = true
            val c0 = consumed.get()
            val r0 = renderedCount()
            main.postDelayed({
                if (released || stEntry == null || !player.isPlaying || !VideoCrop.foreground) return@postDelayed
                if (renderedCount() - r0 < 20 || consumed.get() > c0) return@postDelayed
                VideoCrop.surfaceTextureShowedNothing(context)
                switchToProducer()
            }, 4000)
        }

        private fun switchToProducer() {
            val e = stEntry ?: return
            val s = stSurface
            stEntry = null
            stSurface = null
            attachProducer()
            send(id, "texture", mapOf("texture" to textureId))
            send(id, "log", mapOf("text" to "the SurfaceTexture showed no picture: back to the standard texture"))
            main.postDelayed({
                try {
                    s?.release()
                } catch (_: Exception) {
                }
                try {
                    e.release()
                } catch (_: Exception) {
                }
            }, 1500)
        }

        fun open(url: String, startMs: Long, level: Int, paused: Boolean = false) {
            fpsCount = -1L
            fpsEst = 0.0
            val before = enhance
            enhance = level.coerceIn(0, 2)
            if (before > 0 && enhance == 0) {
                try {
                    player.setVideoEffects(emptyList())
                } catch (_: Throwable) {
                }
            }
            // Effects only when asked: without them ExoPlayer keeps its plain, lightest path.
            if (enhance > 0) try {
                player.setVideoEffects(Enhance.effects(enhance))
                signalOutputSize()
            } catch (e: Throwable) {
                enhance = 0
                send(id, "enhanceoff", mapOf("message" to (e.message ?: "")))
            }
            // Live HLS: the server's own safe distance behind the newest second (a forced 4 s was too
            // close on servers with long segments and stalled) and let ExoPlayer catch up by playing 1-3 % faster or slower, unnoticed.
            val item = if (live) {
                MediaItem.Builder()
                    .setUri(url)
                    .setLiveConfiguration(
                        MediaItem.LiveConfiguration.Builder()
                            .setMinPlaybackSpeed(0.97f)
                            .setMaxPlaybackSpeed(1.03f)
                            .build()
                    )
                    .build()
            } else {
                MediaItem.fromUri(url)
            }
            player.setMediaItem(item, if (!live && startMs > 0) startMs else C.TIME_UNSET)
            player.prepare()
            // Paused = preloaded (a film page fills the buffer before "Watch" is pressed).
            player.playWhenReady = !paused
        }

        /** With effects the renderer must be told the size of the picture surface. */
        @androidx.annotation.OptIn(markerClass = [androidx.media3.common.util.UnstableApi::class])
        private fun signalOutputSize() {
            try {
                for (i in 0 until player.rendererCount) {
                    if (player.getRendererType(i) != C.TRACK_TYPE_VIDEO) continue
                    player.createMessage(player.getRenderer(i))
                        .setType(Renderer.MSG_SET_VIDEO_OUTPUT_RESOLUTION)
                        .setPayload(androidx.media3.common.util.Size(outW, outH))
                        .send()
                }
            } catch (_: Throwable) {
            }
        }

        private fun sendState() {
            if (released) return
            val dur = player.duration
            send(id, "state", mapOf(
                "pos" to player.currentPosition,
                "dur" to (if (dur == C.TIME_UNSET || dur < 0) 0L else dur),
                "buffering" to (player.playbackState == Player.STATE_BUFFERING),
                "playing" to player.isPlaying,
                "idle" to (player.playbackState == Player.STATE_IDLE),
            ))
        }

        private fun describeTracks(t: Tracks): List<Map<String, Any?>> {
            val list = ArrayList<Map<String, Any?>>()
            t.groups.forEachIndexed { g, group ->
                val kind = when (group.type) {
                    C.TRACK_TYPE_AUDIO -> "a"
                    C.TRACK_TYPE_TEXT -> "s"
                    C.TRACK_TYPE_VIDEO -> "v"
                    else -> return@forEachIndexed
                }
                for (i in 0 until group.length) {
                    if (!group.isTrackSupported(i, true)) continue
                    val f = group.getTrackFormat(i)
                    list.add(mapOf(
                        "kind" to kind,
                        "id" to "$kind:$g:$i",
                        "language" to f.language,
                        "label" to f.label,
                        "w" to (if (f.width > 0) f.width else null),
                        "h" to (if (f.height > 0) f.height else null),
                        "bitrate" to (if (f.bitrate > 0) f.bitrate else null),
                        "selected" to group.isTrackSelected(i),
                    ))
                }
            }
            return list
        }

        /** kind: a / s / v; track: "kind:group:index", "no" (subtitles off) or "auto" (best video). */
        fun selectTrack(kind: String, track: String) {
            val type = when (kind) {
                "a" -> C.TRACK_TYPE_AUDIO
                "s" -> C.TRACK_TYPE_TEXT
                "v" -> C.TRACK_TYPE_VIDEO
                else -> return
            }
            val b = player.trackSelectionParameters.buildUpon()
            if (track == "no") {
                b.setTrackTypeDisabled(type, true)
            } else if (track == "auto") {
                b.setTrackTypeDisabled(type, false).clearOverridesOfType(type)
            } else {
                val parts = track.split(':')
                val g = parts.getOrNull(1)?.toIntOrNull() ?: return
                val i = parts.getOrNull(2)?.toIntOrNull() ?: return
                val group = tracks.groups.getOrNull(g) ?: return
                b.setTrackTypeDisabled(type, false)
                    .setOverrideForType(TrackSelectionOverride(group.mediaTrackGroup, i))
            }
            player.trackSelectionParameters = b.build()
        }

        private var fpsCount = -1L
        private var fpsAt = 0L
        private var fpsEst = 0.0

        /** Pictures a second measured from the frames actually shown (TS streams rarely say). */
        private fun measureFps() {
            val c = player.videoDecoderCounters ?: return
            c.ensureUpdated()
            val n = c.renderedOutputBufferCount.toLong()
            val now = android.os.SystemClock.elapsedRealtime()
            if (fpsCount >= 0 && n > fpsCount && now - fpsAt >= 800) {
                fpsEst = (n - fpsCount) * 1000.0 / (now - fpsAt)
            }
            if (fpsCount < 0 || now - fpsAt >= 800) {
                fpsCount = n
                fpsAt = now
            }
        }

        fun facts(): Map<String, Any?> {
            try {
                measureFps()
            } catch (_: Throwable) {
            }
            val v = player.videoFormat
            val a = player.audioFormat
            return mapOf(
                "video" to (v?.sampleMimeType ?: ""),
                "fps" to (v?.frameRate ?: 0f).toDouble(),
                "fpsEst" to fpsEst,
                "decoder" to decoder,
                "audio" to (a?.sampleMimeType ?: ""),
                "dropped" to dropped,
                "enhance" to enhance,
                "surface" to (if (stEntry != null || producer?.handlesCropAndRotation() == true) "SurfaceTexture" else "ImageReader"),
            )
        }

        fun release() {
            if (released) return
            released = true
            main.removeCallbacks(ticker)
            try {
                player.release()
            } catch (_: Exception) {
            }
            try {
                producer?.release()
            } catch (_: Exception) {
            }
            try {
                stSurface?.release()
            } catch (_: Exception) {
            }
            try {
                stEntry?.release()
            } catch (_: Exception) {
            }
            producer = null
            stSurface = null
            stEntry = null
        }
    }
}
