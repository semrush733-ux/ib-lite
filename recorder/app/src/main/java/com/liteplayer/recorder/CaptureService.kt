package com.liteplayer.recorder

import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.util.DisplayMetrics
import android.util.Log
import android.view.Gravity
import android.view.WindowManager
import android.widget.TextView
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream

/**
 * Holds the screen capture: counts down, then records (or takes one picture), and when done
 * opens the Save / Delete screen.
 */
class CaptureService : Service() {

    companion object {
        const val ACTION_START = "start"
        const val ACTION_STOP = "stop"
        const val EXTRA_CODE = "code"
        const val EXTRA_DATA = "data"
        const val EXTRA_SHOT = "shot"
        private const val NOTE_ID = 11

        /** What the service is doing now (the main screen shows it). */
        @Volatile var state: String = ""   // "", "countdown", "recording", "saving"
        @Volatile var startedAt: Long = 0L
        @Volatile var countdownLeft: Int = 0
        @Volatile var lastError: String = ""

        fun stop(ctx: Context) {
            try {
                ctx.startService(Intent(ctx, CaptureService::class.java).setAction(ACTION_STOP))
            } catch (e: Exception) {
                Log.w("LiteRecorder", "stop: $e")
            }
        }
    }

    private val main = Handler(Looper.getMainLooper())
    private var projection: MediaProjection? = null
    private var recorder: Rec? = null
    private var file: File? = null
    private var shot = false
    private var bubble: TextView? = null
    private var wake: PowerManager.WakeLock? = null
    private lateinit var prefs: Prefs
    private var finished = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        prefs = Prefs(this)
        Notes.channels(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                when (state) {
                    "countdown" -> {
                        lastError = ""
                        finish(null)
                    }
                    "recording" -> stopRecording()
                    "" -> if (projection == null) stopSelf()
                }
                return START_NOT_STICKY
            }
            ACTION_START -> begin(intent)
        }
        return START_NOT_STICKY
    }

    private fun note(text: String): Notification {
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val stop = PendingIntent.getService(
            this, 1, Intent(this, CaptureService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val b = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, Notes.CH_REC) else @Suppress("DEPRECATION") Notification.Builder(this)
        return b.setSmallIcon(android.R.drawable.presence_video_online)
            .setContentTitle("Lite Recorder")
            .setContentText(text)
            .setOngoing(true)
            .setContentIntent(open)
            .addAction(Notification.Action.Builder(null as android.graphics.drawable.Icon?, "Stop", stop).build())
            .build()
    }

    private fun begin(intent: Intent) {
        shot = intent.getBooleanExtra(EXTRA_SHOT, false)
        val n = note(if (shot) "Taking a screenshot…" else "Recording the screen…")
        // Android 14: the service must be in the foreground before the capture is taken.
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(NOTE_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        } else {
            startForeground(NOTE_ID, n)
        }
        val code = intent.getIntExtra(EXTRA_CODE, 0)
        @Suppress("DEPRECATION")
        val data: Intent? = if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(EXTRA_DATA, Intent::class.java) else intent.getParcelableExtra(EXTRA_DATA)
        val mpm = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val p = try {
            if (data != null) mpm.getMediaProjection(code, data) else null
        } catch (e: Exception) {
            Log.w("LiteRecorder", "projection: $e")
            null
        }
        if (p == null) {
            lastError = "The TV did not allow screen capture."
            finish(null)
            return
        }
        projection = p
        p.registerCallback(object : MediaProjection.Callback() {
            override fun onStop() {
                // The system (or the cast icon) ended the capture.
                main.post { if (state == "recording") stopRecording() else if (state == "countdown") finish(null) }
            }
        }, main)

        wake = (getSystemService(POWER_SERVICE) as PowerManager)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "LiteRecorder:capture").apply { acquire(4 * 60 * 60 * 1000L) }

        state = "countdown"
        countdownLeft = maxOf(0, prefs.countdown)
        tick()
    }

    private fun tick() {
        if (state != "countdown") return
        if (countdownLeft <= 0) {
            hideBubble()
            // A moment for the countdown bubble to leave the screen before capturing.
            main.postDelayed({ if (state == "countdown") { if (shot) takeShot() else startRecording() } }, 250)
            return
        }
        showBubble("  ${countdownLeft}  ")
        countdownLeft--
        main.postDelayed({ tick() }, 1000)
    }

    // ------------------------------------------------------------------ sizes

    private fun screen(): Triple<Int, Int, Int> {
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        val m = DisplayMetrics()
        @Suppress("DEPRECATION")
        wm.defaultDisplay.getRealMetrics(m)
        return Triple(m.widthPixels, m.heightPixels, m.densityDpi)
    }

    /** Recording size: the screen scaled to the chosen height (even numbers, never bigger than the screen). */
    private fun target(w: Int, h: Int, want: Int): Pair<Int, Int> {
        val shortSide = minOf(w, h)
        val k = if (shortSide > want) want.toDouble() / shortSide else 1.0
        fun even(x: Double) = (Math.round(x).toInt() / 2) * 2
        return even(w * k) to even(h * k)
    }

    // ------------------------------------------------------------------ recording

    private var recDisplay: VirtualDisplay? = null
    private var sizes: List<Pair<Int, Int>> = emptyList()
    private var dpi = 320
    private val diag = ArrayList<String>()

    private fun trace(s: String) {
        Log.i("LiteRecorder", s)
        diag += s
        try {
            val f = File(getExternalFilesDir(null) ?: filesDir, "recorder-log.txt")
            if (f.length() > 100_000) f.delete()
            f.appendText(java.text.SimpleDateFormat("MM-dd HH:mm:ss", java.util.Locale.US).format(java.util.Date()) + "  " + s + "\n")
        } catch (_: Exception) {
        }
    }

    private fun details() = diag.takeLast(3).joinToString("\n")

    private fun bitrateFor(w: Int, h: Int) =
        // About 0.1 bit per pixel per frame: sharp text and smooth motion, sensible file size.
        (w.toLong() * h * prefs.fps / 10).coerceIn(4_000_000L, 16_000_000L).toInt()

    private fun tryMediaRec(f: File): Rec? {
        for ((w, h) in sizes) {
            try {
                f.delete()
                val m = MediaRec(this, w, h, prefs.fps, bitrateFor(w, h), f)
                trace("android recorder ready ${w}x$h")
                return m
            } catch (e: Exception) {
                trace("android recorder ${w}x$h: ${e.javaClass.simpleName} ${e.message ?: ""}")
            }
        }
        return null
    }

    private fun startRecording() {
        val p = projection ?: return finish(null)
        val (sw, sh, d) = screen()
        dpi = d
        sizes = Sizes.candidates(sw, sh, prefs.quality)
        trace("screen ${sw}x$sh dpi $d, Android ${Build.VERSION.SDK_INT}, ${Build.MANUFACTURER} ${Build.MODEL}; sizes $sizes")
        val sound = prefs.sound && hasAudioPermission()
        val f = File(Box.review(this), "rec_${System.currentTimeMillis()}.mp4.tmp")
        var rec: Rec? = null
        // This TV's encoder path could not write a file before: straight to Android's recorder.
        if (prefs.useAndroidRecorder) rec = tryMediaRec(f)
        if (rec == null) loop@ for (basic in listOf(false, true)) {
            for ((w, h) in sizes) {
                try {
                    f.delete()
                    val r = ScreenRecorder(p, w, h, prefs.fps, bitrateFor(w, h), sound, f, basic)
                    r.prepare()
                    trace("encoder ready ${w}x$h basic=$basic sound=${r.withSound}")
                    rec = r
                    break@loop
                } catch (e: Exception) {
                    trace("encoder ${w}x$h basic=$basic: ${e.javaClass.simpleName} ${e.message ?: ""}")
                }
            }
        }
        if (rec == null) rec = tryMediaRec(f)
        if (rec == null) {
            lastError = "Recording could not start on this TV.\n${details()}"
            return finish(null)
        }
        try {
            recDisplay = p.createVirtualDisplay(
                "LiteRecorder", rec.width, rec.height, dpi,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR, rec.surface, null, null,
            )
            rec.begin()
        } catch (e: Exception) {
            trace("start: ${e.javaClass.simpleName} ${e.message ?: ""}")
            rec.abandon()
            lastError = "Recording could not start on this TV.\n${details()}"
            return finish(null)
        }
        recorder = rec
        file = f
        lastError = ""
        state = "recording"
        startedAt = System.currentTimeMillis()
        if (prefs.bubble) showBubble("● REC 0:00") else hideBubble()
        recTick()
        if (rec.frames() >= 0) main.postDelayed({ checkPictures() }, 4000)
    }

    /** The encoder gave no picture: carry on with Android's own recorder (same screen, no gap in the session). */
    private fun checkPictures() {
        if (state != "recording") return
        val r = recorder ?: return
        val n = r.frames()
        val w = r.written()
        if (n != 0 && w != 0) {
            trace("${r.name}: $n pictures in 4 s, $w stored")
            return
        }
        trace("${r.name}: $n pictures, $w stored in 4 s (${r.report()}), switching to the android recorder")
        if (n > 0) prefs.useAndroidRecorder = true
        val f2 = File(Box.review(this), "rec_${System.currentTimeMillis()}.mp4.tmp")
        val m = tryMediaRec(f2)
        val d = recDisplay
        if (m == null || d == null) {
            lastError = "This TV's video encoder gives no picture.\n${details()}"
            stopRecording()
            return
        }
        try {
            d.resize(m.width, m.height, dpi)
            d.surface = m.surface
            m.begin()
        } catch (e: Exception) {
            trace("switch: ${e.javaClass.simpleName} ${e.message ?: ""}")
            m.abandon()
            lastError = "This TV's video encoder gives no picture.\n${details()}"
            stopRecording()
            return
        }
        recorder = m
        file = f2
        startedAt = System.currentTimeMillis()
        Thread { r.abandon() }.start()
    }

    private fun hasAudioPermission() =
        Build.VERSION.SDK_INT >= 29 && checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) == android.content.pm.PackageManager.PERMISSION_GRANTED

    private fun recTick() {
        if (state != "recording") return
        val sec = (System.currentTimeMillis() - startedAt) / 1000
        if (prefs.bubble) showBubble("● REC ${fmtTime(sec)}")
        val limit = prefs.limit
        if (limit > 0 && sec >= limit * 60L) {
            stopRecording()
            return
        }
        // Stop before the TV's storage is full.
        val free = (getExternalFilesDir(null) ?: filesDir).usableSpace
        if (free < 200L * 1024 * 1024) {
            lastError = "Stopped: the TV's storage is almost full."
            stopRecording()
            return
        }
        main.postDelayed({ recTick() }, 1000)
    }

    private fun stopRecording() {
        if (state != "recording") return
        val r = recorder ?: return finish(null)
        state = "saving"
        recorder = null
        hideBubble()
        val secs = (System.currentTimeMillis() - startedAt) / 1000
        Thread {
            val ok = try {
                r.stop()
            } catch (e: Exception) {
                trace("stop: ${e.javaClass.simpleName} ${e.message ?: ""}")
                false
            }
            val size = file?.length() ?: 0
            trace("${r.name} stopped ok=$ok pictures=${r.frames()} size=$size ${r.report()}")
            try { recDisplay?.release() } catch (_: Exception) {}
            recDisplay = null
            val tmp = file
            var done: File? = null
            if (ok && tmp != null && size > 0) {
                done = File(tmp.path.removeSuffix(".tmp"))
                tmp.renameTo(done)
                Box.writeMeta(done, JSONObject().apply {
                    put("kind", "video")
                    put("duration", secs)
                    put("width", r.width)
                    put("height", r.height)
                    put("sound", r.withSound)
                    put("taken", startedAt)
                })
            } else {
                tmp?.delete()
                if (lastError.isEmpty()) lastError = "The recording could not be saved.\n${details()}"
            }
            main.post { finish(done) }
        }.start()
    }

    // ------------------------------------------------------------------ screenshot

    private var reader: ImageReader? = null
    private var shotDisplay: VirtualDisplay? = null

    private fun takeShot() {
        val p = projection ?: return finish(null)
        state = "recording"
        val (w, h, dpi) = screen()
        val ir = ImageReader.newInstance(w, h, PixelFormat.RGBA_8888, 2)
        reader = ir
        val opened = System.currentTimeMillis()
        var taken = false
        ir.setOnImageAvailableListener({ r ->
            val img = try { r.acquireLatestImage() } catch (_: Exception) { null } ?: return@setOnImageAvailableListener
            // Skip the first frames (some TVs send an empty one first).
            if (taken || System.currentTimeMillis() - opened < 400) {
                img.close()
                return@setOnImageAvailableListener
            }
            taken = true
            try {
                val plane = img.planes[0]
                val rowPx = plane.rowStride / plane.pixelStride
                val bmp = Bitmap.createBitmap(rowPx, h, Bitmap.Config.ARGB_8888)
                // The last row can be shorter than the row stride: pad to a full block first.
                val src = plane.buffer
                val full = java.nio.ByteBuffer.allocate(plane.rowStride * h)
                src.rewind()
                full.put(src)
                full.rewind()
                bmp.copyPixelsFromBuffer(full)
                img.close()
                val crop = if (rowPx != w) Bitmap.createBitmap(bmp, 0, 0, w, h) else bmp
                val f = File(Box.review(this), "shot_${System.currentTimeMillis()}.png")
                FileOutputStream(f).use { crop.compress(Bitmap.CompressFormat.PNG, 100, it) }
                Box.writeMeta(f, JSONObject().apply {
                    put("kind", "image")
                    put("width", w)
                    put("height", h)
                    put("taken", System.currentTimeMillis())
                })
                main.post { finish(f) }
            } catch (e: Exception) {
                img.close()
                lastError = "The screenshot could not be saved."
                main.post { finish(null) }
            }
        }, main)
        shotDisplay = p.createVirtualDisplay("LiteShot", w, h, dpi, DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR, ir.surface, null, null)
        main.postDelayed({
            if (!taken) {
                taken = true
                lastError = "The TV sent no picture (some protected apps block screenshots)."
                finish(null)
            }
        }, 6000)
    }

    // ------------------------------------------------------------------ end

    private fun finish(result: File?) {
        if (finished) return
        finished = true
        hideBubble()
        state = ""
        shotDisplay?.release()
        shotDisplay = null
        try { recDisplay?.release() } catch (_: Exception) {}
        recDisplay = null
        reader?.close()
        reader = null
        try {
            projection?.stop()
        } catch (_: Exception) {
        }
        projection = null
        try {
            wake?.release()
        } catch (_: Exception) {
        }
        if (result != null) {
            // Straight to Save / Delete (works when "show on top" is allowed; otherwise the
            // main screen shows it next time it opens, and the notification opens it).
            val i = Intent(this, ReviewActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                .putExtra(ReviewActivity.EXTRA_FILE, result.path)
            try {
                startActivity(i)
            } catch (_: Exception) {
            }
            readyNote(result)
        } else if (lastError.isNotEmpty()) {
            val i = Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                startActivity(i)
            } catch (_: Exception) {
            }
        }
        if (Build.VERSION.SDK_INT >= 24) stopForeground(STOP_FOREGROUND_REMOVE) else @Suppress("DEPRECATION") stopForeground(true)
        stopSelf()
    }

    private fun readyNote(f: File) {
        val pi = PendingIntent.getActivity(
            this, 2,
            Intent(this, ReviewActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK).putExtra(ReviewActivity.EXTRA_FILE, f.path),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val b = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, Notes.CH_REC) else @Suppress("DEPRECATION") Notification.Builder(this)
        val n = b.setSmallIcon(android.R.drawable.ic_menu_save)
            .setContentTitle(if (f.name.endsWith(".png")) "Screenshot ready" else "Recording ready")
            .setContentText("Open to Save (upload) or Delete")
            .setAutoCancel(true)
            .setContentIntent(pi)
            .build()
        try {
            (getSystemService(NOTIFICATION_SERVICE) as android.app.NotificationManager).notify(12, n)
        } catch (_: Exception) {
        }
    }

    // ------------------------------------------------------------------ on-screen bubble

    private fun canOverlay() = Build.VERSION.SDK_INT < 23 || Settings.canDrawOverlays(this)

    private fun showBubble(text: String) {
        if (!canOverlay()) return
        val b = bubble
        if (b != null) {
            b.text = text
            return
        }
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        val tv = TextView(this).apply {
            this.text = text
            setTextColor(Color.WHITE)
            textSize = 22f
            typeface = Typeface.DEFAULT_BOLD
            setPadding(28, 14, 28, 14)
            background = GradientDrawable().apply {
                cornerRadius = 60f
                setColor(Color.parseColor("#E6262F"))
            }
            // Touch screens: tap the bubble to stop.
            setOnClickListener { CaptureService.stop(this@CaptureService) }
        }
        @Suppress("DEPRECATION")
        val type = if (Build.VERSION.SDK_INT >= 26) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY else WindowManager.LayoutParams.TYPE_PHONE
        val lp = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.WRAP_CONTENT, type,
            // Never takes the remote's focus: the app underneath keeps working.
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.END
            x = 40
            y = 40
        }
        try {
            wm.addView(tv, lp)
            bubble = tv
        } catch (e: Exception) {
            Log.w("LiteRecorder", "bubble: $e")
        }
    }

    private fun hideBubble() {
        val b = bubble ?: return
        bubble = null
        try {
            (getSystemService(WINDOW_SERVICE) as WindowManager).removeView(b)
        } catch (_: Exception) {
        }
    }

    override fun onDestroy() {
        hideBubble()
        if (state == "recording" && recorder != null) {
            try { recorder?.stop() } catch (_: Exception) {}
        }
        super.onDestroy()
    }
}
