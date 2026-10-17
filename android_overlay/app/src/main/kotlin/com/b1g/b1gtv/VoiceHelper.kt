package com.b1g.b1gtv

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.speech.RecognizerIntent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Voice for the player (channel "b1g/voice").
 *
 * 1. Assistants: Alexa on Fire TV ("Alexa, pause / play / rewind 30 seconds / fast forward /
 *    next / previous / restart") and the Google Assistant on Android TV send these to the media
 *    session of the app that played last. The session passes them to Flutter as "command"; the
 *    player tells it what is playing ("state"), so the assistant knows what can be done (a live
 *    channel has no pause). Amazon: the voicecommandcontrol permission and the background
 *    meta-data in the manifest (commands arrive at once, without waiting for audio focus).
 *
 * 2. The app's own microphone ("listen"): Android's speech screen (Google's voice typing on phones
 *    and Android / Google TV boxes). The words heard come back to Flutter. Fire TV has no speech
 *    recognizer for apps, so "canListen" is false there and the app shows no microphone.
 */
class VoiceHelper(private val activity: Activity, messenger: BinaryMessenger) {

    companion object {
        const val SPEECH_REQUEST = 4711
    }

    private val channel = MethodChannel(messenger, "b1g/voice")
    private var session: MediaSession? = null
    private var pendingListen: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "state" -> {
                    try {
                        update(call.arguments as? Map<*, *>)
                    } catch (_: Exception) {
                    }
                    result.success(null)
                }
                "canListen" -> result.success(canListen())
                "listen" -> listen(call.arguments as? Map<*, *>, result)
                else -> result.notImplemented()
            }
        }
    }

    // ------------------------------------------------------------------ assistants

    private fun ensureSession(): MediaSession {
        session?.let { return it }
        val s = MediaSession(activity.applicationContext, "LitePlayer")
        s.setCallback(object : MediaSession.Callback() {
            override fun onPlay() = send("play")
            override fun onPause() = send("pause")
            override fun onStop() = send("stop")
            override fun onSkipToNext() = send("next")
            override fun onSkipToPrevious() = send("previous")
            override fun onFastForward() = send("forward")
            override fun onRewind() = send("rewind")
            // Alexa's "rewind 30 seconds", "fast forward", "restart" (0) all come as a position.
            override fun onSeekTo(pos: Long) = send("seek", pos)
        })
        @Suppress("DEPRECATION")
        s.setFlags(MediaSession.FLAG_HANDLES_MEDIA_BUTTONS or MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS)
        session = s
        return s
    }

    private fun send(command: String, position: Long = -1L) {
        activity.runOnUiThread {
            try {
                channel.invokeMethod("command", mapOf("command" to command, "position" to position))
            } catch (_: Exception) {
            }
        }
    }

    private fun flag(a: Map<*, *>, key: String) = a[key] == true

    private fun update(a: Map<*, *>?) {
        if (a == null) return
        if (!flag(a, "active")) {
            // Nothing playing: the assistants have nothing to control here.
            session?.let {
                it.setPlaybackState(PlaybackState.Builder().setState(PlaybackState.STATE_STOPPED, 0L, 0f).build())
                it.isActive = false
            }
            return
        }
        val s = ensureSession()
        val playing = flag(a, "playing")
        val position = (a["position"] as? Number)?.toLong() ?: 0L
        val duration = (a["duration"] as? Number)?.toLong() ?: 0L
        val speed = (a["speed"] as? Number)?.toFloat() ?: 1f
        var actions = PlaybackState.ACTION_PLAY or PlaybackState.ACTION_STOP
        if (flag(a, "canPause")) actions = actions or PlaybackState.ACTION_PAUSE or PlaybackState.ACTION_PLAY_PAUSE
        if (flag(a, "canSeek")) {
            actions = actions or PlaybackState.ACTION_SEEK_TO or PlaybackState.ACTION_FAST_FORWARD or PlaybackState.ACTION_REWIND
        }
        if (flag(a, "canNext")) actions = actions or PlaybackState.ACTION_SKIP_TO_NEXT
        if (flag(a, "canPrevious")) actions = actions or PlaybackState.ACTION_SKIP_TO_PREVIOUS
        val state = when {
            flag(a, "buffering") -> PlaybackState.STATE_BUFFERING
            playing -> PlaybackState.STATE_PLAYING
            else -> PlaybackState.STATE_PAUSED
        }
        s.setPlaybackState(
            PlaybackState.Builder()
                .setActions(actions)
                .setState(state, position, if (playing) speed else 0f)
                .build()
        )
        val title = a["title"] as? String ?: ""
        val meta = MediaMetadata.Builder().putString(MediaMetadata.METADATA_KEY_TITLE, title)
        if (duration > 0) meta.putLong(MediaMetadata.METADATA_KEY_DURATION, duration)
        s.setMetadata(meta.build())
        if (!s.isActive) s.isActive = true
    }

    // ------------------------------------------------------------------ microphone

    private fun speechIntent(prompt: String?, language: String?): Intent {
        val i = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
        i.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
        i.putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 5)
        if (!prompt.isNullOrEmpty()) i.putExtra(RecognizerIntent.EXTRA_PROMPT, prompt)
        if (!language.isNullOrEmpty()) i.putExtra(RecognizerIntent.EXTRA_LANGUAGE, language)
        return i
    }

    /** A speech screen is there to start (never on Fire TV: Amazon has none for apps). */
    private fun canListen(): Boolean {
        if (Build.MANUFACTURER.equals("Amazon", ignoreCase = true)) return false
        return try {
            activity.packageManager.queryIntentActivities(Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH), 0).isNotEmpty()
        } catch (_: Exception) {
            false
        }
    }

    private fun listen(a: Map<*, *>?, result: MethodChannel.Result) {
        // Only one at a time: an older request that never came back gets "nothing heard".
        pendingListen?.success(emptyList<String>())
        pendingListen = result
        try {
            @Suppress("DEPRECATION")
            activity.startActivityForResult(speechIntent(a?.get("prompt") as? String, a?.get("language") as? String), SPEECH_REQUEST)
        } catch (e: ActivityNotFoundException) {
            pendingListen = null
            result.error("unavailable", "No speech recognizer on this device", null)
        } catch (e: Exception) {
            pendingListen = null
            result.error("failed", e.message, null)
        }
    }

    /** True when this was the speech screen's answer. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != SPEECH_REQUEST) return false
        val r = pendingListen
        pendingListen = null
        val words = if (resultCode == Activity.RESULT_OK) data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS) else null
        try {
            r?.success(words?.toList() ?: emptyList<String>())
        } catch (_: Exception) {
        }
        return true
    }

    fun release() {
        try {
            pendingListen?.success(emptyList<String>())
        } catch (_: Exception) {
        }
        pendingListen = null
        session?.release()
        session = null
        channel.setMethodCallHandler(null)
    }
}
