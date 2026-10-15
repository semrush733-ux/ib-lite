package com.b1g.b1gtv

import android.content.Context
import android.os.Handler
import android.os.Looper
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
 * tracks, cues (subtitle text), ended and error.
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
                result.success(mapOf("id" to id, "texture" to s.textureId))
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
        private val producer: TextureRegistry.SurfaceProducer = textures.createSurfaceProducer()
        val textureId: Long = producer.id()
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
            val renderers = DefaultRenderersFactory(context)
                .setEnableDecoderFallback(true)
                .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON)
            player = ExoPlayer.Builder(context, renderers)
                .setMediaSourceFactory(DefaultMediaSourceFactory(DefaultDataSource.Factory(context, http)))
                .setLoadControl(load)
                .build()

            producer.setSize(1920, 1080)
            producer.setCallback(object : TextureRegistry.SurfaceProducer.Callback {
                override fun onSurfaceAvailable() {
                    if (!released) player.setVideoSurface(producer.surface)
                }

                override fun onSurfaceCleanup() {
                    if (!released) player.setVideoSurface(null)
                }
            })
            player.setVideoSurface(producer.surface)

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
                    producer.setSize(size.width, size.height)
                    player.setVideoSurface(producer.surface)
                    outW = size.width
                    outH = size.height
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
                producer.release()
            } catch (_: Exception) {
            }
        }
    }
}
