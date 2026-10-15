package com.liteplayer.recorder

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import org.json.JSONObject
import java.io.File

/** Settings kept on the TV. */
class Prefs(ctx: Context) {
    private val p = ctx.getSharedPreferences("rec", Context.MODE_PRIVATE)

    var site: String
        get() = p.getString("site", null) ?: BuildConfig.SITE
        set(v) = p.edit().putString("site", v.trim().trimEnd('/')).apply()
    var token: String
        get() = p.getString("token", "") ?: ""
        set(v) = p.edit().putString("token", v).apply()
    var siteName: String
        get() = p.getString("siteName", "") ?: ""
        set(v) = p.edit().putString("siteName", v).apply()

    /** Picture height: 1080 or 720. */
    var quality: Int
        get() = p.getInt("quality", 1080)
        set(v) = p.edit().putInt("quality", v).apply()
    var fps: Int
        get() = p.getInt("fps", 30)
        set(v) = p.edit().putInt("fps", v).apply()
    var sound: Boolean
        get() = p.getBoolean("sound", true)
        set(v) = p.edit().putBoolean("sound", v).apply()
    /** Seconds before recording / the screenshot starts (time to open the other app). */
    var countdown: Int
        get() = p.getInt("countdown", 5)
        set(v) = p.edit().putInt("countdown", v).apply()
    /** Recording stops by itself after this many minutes (0 = only when stopped). */
    var limit: Int
        get() = p.getInt("limit", 0)
        set(v) = p.edit().putInt("limit", v).apply()
    /** A small "REC" timer on screen (it is in the video too). */
    var bubble: Boolean
        get() = p.getBoolean("bubble", false)
        set(v) = p.edit().putBoolean("bubble", v).apply()

    /** Set when the encoder path cannot write a file on this TV (then Android's recorder is used). */
    var useAndroidRecorder: Boolean
        get() = p.getBoolean("useAndroidRecorder", false)
        set(v) = p.edit().putBoolean("useAndroidRecorder", v).apply()

    var uploadedCount: Int
        get() = p.getInt("uploaded", 0)
        set(v) = p.edit().putInt("uploaded", v).apply()
    var lastError: String
        get() = p.getString("lastError", "") ?: ""
        set(v) = p.edit().putString("lastError", v).apply()

    val paired get() = token.isNotEmpty() && site.isNotEmpty()
}

/**
 * Files on the TV: "review" holds new captures waiting for Save / Delete, "outbox" the saved
 * ones waiting to upload. Each file has a .json next to it (kind, length, size, time).
 */
object Box {
    fun review(ctx: Context) = File(ctx.getExternalFilesDir(null) ?: ctx.filesDir, "review").apply { mkdirs() }
    fun outbox(ctx: Context) = File(ctx.getExternalFilesDir(null) ?: ctx.filesDir, "outbox").apply { mkdirs() }

    fun list(dir: File): List<File> =
        (dir.listFiles() ?: emptyArray()).filter {
            it.isFile && it.length() > 0 && (it.name.endsWith(".mp4") || it.name.endsWith(".png") || it.name.endsWith(".jpg"))
        }
            .sortedBy { it.lastModified() }

    fun meta(f: File): JSONObject = try {
        JSONObject(File(f.path + ".json").readText())
    } catch (_: Exception) {
        JSONObject()
    }

    fun writeMeta(f: File, m: JSONObject) {
        File(f.path + ".json").writeText(m.toString())
    }

    fun delete(f: File) {
        f.delete()
        File(f.path + ".json").delete()
    }

    fun move(f: File, dir: File): File {
        val to = File(dir, f.name)
        if (!f.renameTo(to)) {
            f.copyTo(to, overwrite = true)
            f.delete()
        }
        File(f.path + ".json").let { j -> if (j.exists()) { j.copyTo(File(to.path + ".json"), true); j.delete() } }
        return to
    }

    /** Partly written captures left by a crash or power cut. */
    fun clean(ctx: Context) {
        // Never while a recording is being written (its file is a .tmp until it stops).
        if (CaptureService.state.isNotEmpty()) return
        (review(ctx).listFiles() ?: emptyArray()).forEach {
            if (it.name.endsWith(".tmp") && System.currentTimeMillis() - it.lastModified() > 60_000) it.delete()
            if (it.name.endsWith(".json") && !File(it.path.removeSuffix(".json")).exists()) it.delete()
        }
    }
}

object Notes {
    const val CH_REC = "rec"
    const val CH_UP = "upload"

    fun channels(ctx: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val nm = ctx.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(CH_REC, "Recording", NotificationManager.IMPORTANCE_LOW))
        nm.createNotificationChannel(NotificationChannel(CH_UP, "Uploads", NotificationManager.IMPORTANCE_LOW))
    }
}

fun fmtSize(b: Long): String = when {
    b >= 1L shl 30 -> String.format("%.2f GB", b / 1073741824.0)
    b >= 1L shl 20 -> String.format("%.1f MB", b / 1048576.0)
    else -> "${maxOf(1, b / 1024)} KB"
}

fun fmtTime(sec: Long): String = String.format("%d:%02d", sec / 60, sec % 60)
