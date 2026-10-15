package com.liteplayer.recorder

import android.annotation.SuppressLint
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioPlaybackCaptureConfiguration
import android.media.AudioRecord
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.media.projection.MediaProjection
import android.os.Build
import android.util.Log
import android.view.Surface
import java.io.File
import java.nio.ByteBuffer

/**
 * Records the screen (and, on Android 10+, the sound the apps play) into an MP4.
 * Video: H.264 straight from the screen into the hardware encoder (no copies, smooth).
 * Sound: what apps play (not the microphone), AAC 48 kHz stereo.
 */
class ScreenRecorder(
    private val projection: MediaProjection,
    val width: Int,
    val height: Int,
    private val dpi: Int,
    private val fps: Int,
    private val bitrate: Int,
    wantAudio: Boolean,
    private val out: File,
) {
    private val tag = "LiteRecorder"

    private lateinit var video: MediaCodec
    private var input: Surface? = null
    private var display: VirtualDisplay? = null
    private var audio: MediaCodec? = null
    private var mic: AudioRecord? = null
    private val muxer = MediaMuxer(out.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)

    private val lock = Object()
    private var hasAudio = wantAudio && Build.VERSION.SDK_INT >= 29
    private var vTrack = -1
    private var aTrack = -1
    private var started = false
    private var startNs = 0L
    private var lastV = -1L
    private var lastA = -1L
    private var videoFormatAt = 0L
    private val waiting = ArrayList<Triple<Boolean, ByteArray, MediaCodec.BufferInfo>>()

    @Volatile private var stopping = false
    private var vThread: Thread? = null
    private var aThread: Thread? = null

    /** True when this recording has the apps' sound. */
    val withSound get() = hasAudio

    @SuppressLint("MissingPermission")
    fun start() {
        startNs = System.nanoTime()
        val f = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            setInteger(MediaFormat.KEY_BIT_RATE, bitrate)
            setInteger(MediaFormat.KEY_FRAME_RATE, fps)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
            // A still screen keeps sending frames, so the video timeline stays even.
            setLong(MediaFormat.KEY_REPEAT_PREVIOUS_FRAME_AFTER, 1_000_000L / fps)
            if (Build.VERSION.SDK_INT >= 23) setInteger(MediaFormat.KEY_PRIORITY, 0)
        }
        video = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
        video.configure(f, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        input = video.createInputSurface()
        video.start()

        if (hasAudio) {
            try {
                startAudio()
            } catch (e: Throwable) {
                Log.w(tag, "no sound: $e")
                releaseAudio()
                hasAudio = false
            }
        }

        display = projection.createVirtualDisplay(
            "LiteRecorder", width, height, dpi,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR, input, null, null,
        )
        vThread = Thread({ drainVideo() }, "rec-video").apply { start() }
        if (hasAudio) aThread = Thread({ pumpAudio() }, "rec-audio").apply { start() }
    }

    @SuppressLint("MissingPermission")
    private fun startAudio() {
        if (Build.VERSION.SDK_INT < 29) throw IllegalStateException("Android 10+ only")
        val cfg = AudioPlaybackCaptureConfiguration.Builder(projection)
            .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
            .addMatchingUsage(AudioAttributes.USAGE_GAME)
            .addMatchingUsage(AudioAttributes.USAGE_UNKNOWN)
            .build()
        val rate = 48000
        val min = AudioRecord.getMinBufferSize(rate, AudioFormat.CHANNEL_IN_STEREO, AudioFormat.ENCODING_PCM_16BIT)
        val rec = AudioRecord.Builder()
            .setAudioFormat(
                AudioFormat.Builder().setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(rate).setChannelMask(AudioFormat.CHANNEL_IN_STEREO).build()
            )
            .setBufferSizeInBytes(maxOf(min * 4, 32768))
            .setAudioPlaybackCaptureConfig(cfg)
            .build()
        if (rec.state != AudioRecord.STATE_INITIALIZED) {
            rec.release()
            throw IllegalStateException("sound capture not available")
        }
        mic = rec
        val af = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, rate, 2).apply {
            setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
            setInteger(MediaFormat.KEY_BIT_RATE, 192000)
            setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 16384)
        }
        val enc = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
        enc.configure(af, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        enc.start()
        audio = enc
        rec.startRecording()
    }

    // ------------------------------------------------------------------ muxing

    private fun addTrack(isVideo: Boolean, format: MediaFormat) {
        synchronized(lock) {
            if (started) return
            if (isVideo) {
                vTrack = muxer.addTrack(format)
                videoFormatAt = System.nanoTime()
            } else {
                aTrack = muxer.addTrack(format)
            }
            maybeStart()
        }
    }

    /** Starts the file once both tracks are known (or without sound when it never comes). */
    private fun maybeStart(force: Boolean = false) {
        if (started || vTrack < 0) return
        if (hasAudio && aTrack < 0 && !force) return
        if (hasAudio && aTrack < 0) hasAudio = false
        muxer.start()
        started = true
        for ((v, data, info) in waiting) put(v, ByteBuffer.wrap(data), info)
        waiting.clear()
    }

    private var vOff = Long.MIN_VALUE
    private var aOff = Long.MIN_VALUE

    /** Time from the start of the recording, whatever clock the encoder's stamps use. */
    private fun rel(isVideo: Boolean, pts: Long): Long {
        val sinceStart = System.nanoTime() / 1000 - startNs / 1000
        var off = if (isVideo) vOff else aOff
        if (off == Long.MIN_VALUE) {
            // Normally the stamps are on the same clock as System.nanoTime(); if not, line them up now.
            off = if (Math.abs(pts - System.nanoTime() / 1000) < 2_000_000L) startNs / 1000 else pts - sinceStart
            if (isVideo) vOff = off else aOff = off
        }
        return pts - off
    }

    private fun write(isVideo: Boolean, buf: ByteBuffer, orig: MediaCodec.BufferInfo) {
        synchronized(lock) {
            if (!isVideo && !hasAudio) return
            if (orig.size <= 0) return
            val info = MediaCodec.BufferInfo().apply { set(orig.offset, orig.size, rel(isVideo, orig.presentationTimeUs), orig.flags) }
            if (!started) {
                // Sound did not start within 3 s: the video goes on without it.
                if (isVideo && hasAudio && aTrack < 0 && videoFormatAt > 0 && System.nanoTime() - videoFormatAt > 3_000_000_000L) {
                    maybeStart(force = true)
                } else {
                    if (waiting.size < 600) {
                        val copy = ByteArray(info.size)
                        buf.position(info.offset); buf.limit(info.offset + info.size); buf.get(copy)
                        val i = MediaCodec.BufferInfo().apply { set(0, info.size, info.presentationTimeUs, info.flags) }
                        waiting.add(Triple(isVideo, copy, i))
                    }
                    return
                }
            }
            put(isVideo, buf, info)
        }
    }

    private fun put(isVideo: Boolean, buf: ByteBuffer, info: MediaCodec.BufferInfo) {
        if (info.size <= 0) return
        var pts = info.presentationTimeUs
        if (pts < 0) return
        if (isVideo) {
            if (pts <= lastV) pts = lastV + 1
            lastV = pts
        } else {
            if (pts <= lastA) pts = lastA + 1
            lastA = pts
        }
        val i = MediaCodec.BufferInfo().apply { set(info.offset, info.size, pts, info.flags) }
        buf.position(info.offset)
        buf.limit(info.offset + info.size)
        try {
            muxer.writeSampleData(if (isVideo) vTrack else aTrack, buf, i)
        } catch (e: Exception) {
            Log.w(tag, "write: $e")
        }
    }

    // ------------------------------------------------------------------ threads

    private fun drainVideo() {
        val info = MediaCodec.BufferInfo()
        try {
            while (true) {
                val idx = video.dequeueOutputBuffer(info, 10_000)
                when {
                    idx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> addTrack(true, video.outputFormat)
                    idx >= 0 -> {
                        val buf = video.getOutputBuffer(idx)
                        if (buf != null && info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0) write(true, buf, info)
                        video.releaseOutputBuffer(idx, false)
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
                    }
                }
            }
        } catch (e: Exception) {
            Log.w(tag, "video: $e")
        }
    }

    private fun pumpAudio() {
        val enc = audio ?: return
        val rec = mic ?: return
        val info = MediaCodec.BufferInfo()
        val bytesPerSec = 48000L * 2 * 2
        var total = 0L
        var firstUs = -1L
        var eosSent = false
        try {
            while (true) {
                if (!eosSent) {
                    val inIdx = enc.dequeueInputBuffer(10_000)
                    if (inIdx >= 0) {
                        val b = enc.getInputBuffer(inIdx)!!
                        b.clear()
                        if (stopping) {
                            enc.queueInputBuffer(inIdx, 0, 0, ptsOf(firstUs, total, bytesPerSec), MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            eosSent = true
                        } else {
                            val n = rec.read(b, minOf(b.capacity(), 8192))
                            if (n > 0) {
                                if (firstUs < 0) firstUs = System.nanoTime() / 1000 - n * 1_000_000L / bytesPerSec
                                enc.queueInputBuffer(inIdx, 0, n, ptsOf(firstUs, total, bytesPerSec), 0)
                                total += n
                            } else {
                                enc.queueInputBuffer(inIdx, 0, 0, ptsOf(firstUs, total, bytesPerSec), 0)
                                Thread.sleep(5)
                            }
                        }
                    }
                }
                val o = enc.dequeueOutputBuffer(info, if (eosSent) 10_000 else 0)
                if (o == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    addTrack(false, enc.outputFormat)
                } else if (o >= 0) {
                    val buf = enc.getOutputBuffer(o)
                    if (buf != null && info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0) write(false, buf, info)
                    enc.releaseOutputBuffer(o, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
                }
            }
        } catch (e: Exception) {
            Log.w(tag, "audio: $e")
        }
    }

    private fun ptsOf(firstUs: Long, bytes: Long, bytesPerSec: Long) =
        (if (firstUs < 0) System.nanoTime() / 1000 else firstUs) + bytes * 1_000_000L / bytesPerSec

    /** Ends the file. Returns true when it holds video. */
    fun stop(): Boolean {
        stopping = true
        try {
            video.signalEndOfInputStream()
        } catch (_: Exception) {
        }
        vThread?.join(6000)
        aThread?.join(4000)
        display?.release()
        display = null
        val ok: Boolean
        synchronized(lock) {
            if (!started && vTrack >= 0) maybeStart(force = true)
            ok = started && lastV > 0
            try {
                if (started) muxer.stop()
            } catch (e: Exception) {
                Log.w(tag, "muxer stop: $e")
            }
            try {
                muxer.release()
            } catch (_: Exception) {
            }
        }
        try {
            video.stop()
        } catch (_: Exception) {
        }
        video.release()
        input?.release()
        releaseAudio()
        return ok
    }

    private fun releaseAudio() {
        try {
            mic?.stop()
        } catch (_: Exception) {
        }
        mic?.release()
        mic = null
        try {
            audio?.stop()
        } catch (_: Exception) {
        }
        audio?.release()
        audio = null
    }

    /** Length recorded so far, in seconds. */
    fun seconds(): Long = maxOf(0, lastV / 1_000_000L)
}
