package com.liteplayer.recorder

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import java.io.File
import java.io.RandomAccessFile

/**
 * Sends the saved files to the website, one after another, in 2 MB pieces. A cut connection
 * carries on from the last piece; the file leaves the TV only once the website has it.
 */
class UploadService : Service() {

    companion object {
        @Volatile var running = false
        @Volatile var current: String = ""
        @Volatile var percent: Int = 0
        private const val NOTE_ID = 21

        fun kick(ctx: Context) {
            if (running) return
            if (Box.list(Box.outbox(ctx)).isEmpty()) return
            val i = Intent(ctx, UploadService::class.java)
            try {
                if (Build.VERSION.SDK_INT >= 26) ctx.startForegroundService(i) else ctx.startService(i)
            } catch (e: Exception) {
                Log.w("LiteRecorder", "upload start: $e")
            }
        }
    }

    private lateinit var prefs: Prefs
    private var wake: PowerManager.WakeLock? = null
    private var lastNote = 0L

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        prefs = Prefs(this)
        Notes.channels(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val n = note("Uploading…", 0)
        if (Build.VERSION.SDK_INT >= 29) startForeground(NOTE_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        else startForeground(NOTE_ID, n)
        if (running) return START_NOT_STICKY
        running = true
        wake = (getSystemService(POWER_SERVICE) as PowerManager)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "LiteRecorder:upload").apply { acquire(3 * 60 * 60 * 1000L) }
        Thread { work() }.start()
        return START_NOT_STICKY
    }

    private fun note(text: String, pct: Int): Notification {
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val b = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, Notes.CH_UP) else @Suppress("DEPRECATION") Notification.Builder(this)
        return b.setSmallIcon(android.R.drawable.stat_sys_upload)
            .setContentTitle("Lite Recorder")
            .setContentText(text)
            .setProgress(100, pct, pct <= 0)
            .setOngoing(true)
            .setContentIntent(open)
            .build()
    }

    private fun show(text: String, pct: Int) {
        val now = System.currentTimeMillis()
        if (now - lastNote < 1000 && pct in 1..99) return
        lastNote = now
        try {
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).notify(NOTE_ID, note(text, pct))
        } catch (_: Exception) {
        }
    }

    private fun work() {
        try {
            var failsInRow = 0
            while (true) {
                if (!prefs.paired) {
                    prefs.lastError = "Not paired with a website yet."
                    break
                }
                val f = Box.list(Box.outbox(this)).firstOrNull() ?: break
                try {
                    upload(f)
                    Box.delete(f)
                    prefs.uploadedCount = prefs.uploadedCount + 1
                    prefs.lastError = ""
                    failsInRow = 0
                } catch (e: ApiError) {
                    Log.w("LiteRecorder", "upload: ${e.status} ${e.message}")
                    prefs.lastError = e.message ?: "Upload failed."
                    if (e.status == 401) break           // TV removed on the website: pair again
                    if (e.status in 400..499 && e.status != 409 && e.status != 429) {
                        // The website refuses this file (type / size): keep it out of the way.
                        f.renameTo(File(f.path + ".refused"))
                        continue
                    }
                    if (++failsInRow >= 6) break
                    Thread.sleep(minOf(60_000L, 5_000L * failsInRow))
                } catch (e: Exception) {
                    Log.w("LiteRecorder", "upload: $e")
                    prefs.lastError = "No connection to the website (will try again)."
                    if (++failsInRow >= 6) break
                    Thread.sleep(minOf(60_000L, 5_000L * failsInRow))
                }
            }
        } finally {
            running = false
            current = ""
            percent = 0
            try {
                wake?.release()
            } catch (_: Exception) {
            }
            if (Build.VERSION.SDK_INT >= 24) stopForeground(STOP_FOREGROUND_REMOVE) else @Suppress("DEPRECATION") stopForeground(true)
            stopSelf()
        }
    }

    private fun upload(f: File) {
        val net = Net(prefs.site, prefs.token)
        val m = Box.meta(f)
        val size = f.length()
        current = f.name
        percent = 0
        show("Uploading ${f.name}", 0)
        val start = net.post("upload/start", mapOf(
            "name" to f.name,
            "size" to size.toString(),
            "key" to f.name.filter { it.isLetterOrDigit() },
            "duration" to m.optLong("duration", 0).toString(),
            "width" to m.optInt("width", 0).toString(),
            "height" to m.optInt("height", 0).toString(),
            "taken" to m.optLong("taken", f.lastModified()).toString(),
        ))
        if (start.optBoolean("done")) return
        val id = start.getString("id")
        var offset = start.optLong("received", 0)
        val piece = start.optInt("chunk", 2 * 1024 * 1024).coerceIn(256 * 1024, 8 * 1024 * 1024)
        val buf = ByteArray(piece)
        RandomAccessFile(f, "r").use { raf ->
            var tries = 0
            while (offset < size) {
                raf.seek(offset)
                val n = raf.read(buf, 0, minOf(piece.toLong(), size - offset).toInt())
                if (n <= 0) break
                try {
                    offset = net.chunk(id, offset, buf, n).getLong("received")
                    tries = 0
                } catch (e: ApiError) {
                    if (e.status == 409 && e.body.has("received")) {
                        offset = e.body.getLong("received")   // out of step: go on from what the site has
                    } else if (e.status >= 500 && ++tries < 5) {
                        Thread.sleep(3000L * tries)
                    } else throw e
                } catch (e: java.io.IOException) {
                    if (++tries >= 5) throw e
                    Thread.sleep(3000L * tries)
                    // Ask the website how much arrived before the cut.
                    try {
                        offset = net.get("upload/status", mapOf("id" to id)).optLong("received", offset)
                    } catch (_: Exception) {
                    }
                }
                percent = (offset * 100 / size).toInt()
                show("Uploading ${f.name} — $percent%", percent.coerceAtLeast(1))
            }
        }
        net.post("upload/finish", mapOf("id" to id))
        show("Uploaded ${f.name}", 100)
    }

    override fun onDestroy() {
        running = false
        super.onDestroy()
    }
}
