package com.liteplayer.recorder

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.graphics.BitmapFactory
import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import android.widget.VideoView
import java.io.File

/**
 * After a recording or screenshot: watch it, then Save (upload to the website) or Delete.
 */
class ReviewActivity : Activity() {

    companion object {
        const val EXTRA_FILE = "file"
    }

    private lateinit var prefs: Prefs
    private var file: File? = null
    private var video: VideoView? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        prefs = Prefs(this)
        show(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        show(intent)
    }

    private fun pick(intent: Intent?): File? {
        val asked = intent?.getStringExtra(EXTRA_FILE)?.let { File(it) }
        if (asked != null && asked.exists()) return asked
        return Box.list(Box.review(this)).lastOrNull()
    }

    private fun show(intent: Intent?) {
        video?.stopPlayback()
        video = null
        val f = pick(intent)
        if (f == null) {
            finish()
            return
        }
        file = f
        val c = this
        val m = Box.meta(f)
        val isVideo = f.name.endsWith(".mp4")

        val root = LinearLayout(c).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Ui.BG)
            setPadding(Ui.dp(c, 24), Ui.dp(c, 18), Ui.dp(c, 24), Ui.dp(c, 18))
        }
        root.addView(Ui.text(c, if (isVideo) "New recording" else "New screenshot", 24f, Color.WHITE, true))

        val preview = FrameLayout(c).apply {
            setBackgroundColor(Color.BLACK)
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f).apply {
                topMargin = Ui.dp(c, 8)
                bottomMargin = Ui.dp(c, 8)
            }
        }
        if (isVideo) {
            val v = VideoView(c)
            v.setVideoPath(f.path)
            v.setOnPreparedListener { mp ->
                mp.isLooping = true
                v.start()
            }
            v.setOnErrorListener { _, _, _ -> true } // the file is still fine to upload
            v.isFocusable = false
            preview.addView(v, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT, Gravity.CENTER))
            video = v
        } else {
            val iv = ImageView(c).apply { scaleType = ImageView.ScaleType.FIT_CENTER }
            try {
                val o = BitmapFactory.Options().apply { inSampleSize = 2 }
                iv.setImageBitmap(BitmapFactory.decodeFile(f.path, o))
            } catch (_: Throwable) {
            }
            preview.addView(iv, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
        }
        root.addView(preview)

        val parts = mutableListOf<String>()
        if (isVideo) parts += fmtTime(m.optLong("duration", 0))
        parts += fmtSize(f.length())
        if (m.optInt("width") > 0) parts += "${m.optInt("width")} x ${m.optInt("height")}"
        if (isVideo) parts += if (m.optBoolean("sound")) "with sound" else "no sound"
        val waiting = Box.list(Box.review(this)).size
        if (waiting > 1) parts += "$waiting waiting"
        root.addView(Ui.text(c, parts.joinToString("  ·  "), 16f))

        val row = LinearLayout(c).apply { orientation = LinearLayout.HORIZONTAL }
        val save = Ui.button(c, "✓  Save — upload to website", true) { save() }
        val del = Ui.button(c, "✕  Delete") { askDelete() }
        val later = Ui.button(c, "Later") { finish() }
        for ((b, w) in listOf(save to 2f, del to 1f, later to 1f)) {
            b.gravity = Gravity.CENTER
            b.layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, w).apply {
                marginStart = Ui.dp(c, 6)
                marginEnd = Ui.dp(c, 6)
            }
            row.addView(b)
        }
        root.addView(row)
        if (!prefs.paired) {
            root.addView(Ui.text(c, "Not paired with a website yet: Save keeps it on the TV and uploads it after pairing.", 14f, Ui.RED))
        }
        setContentView(root)
        save.requestFocus()
    }

    private fun save() {
        val f = file ?: return
        video?.stopPlayback()
        Box.move(f, Box.outbox(this))
        UploadService.kick(this)
        Toast.makeText(this, if (prefs.paired) "Uploading to the website…" else "Saved. Pair with your website to upload.", Toast.LENGTH_LONG).show()
        nextOrFinish()
    }

    private fun askDelete() {
        val f = file ?: return
        AlertDialog.Builder(this, android.R.style.Theme_Material_Dialog_Alert)
            .setTitle(if (f.name.endsWith(".mp4")) "Delete this recording?" else "Delete this screenshot?")
            .setMessage("It is removed from the TV and not uploaded.")
            .setPositiveButton("Delete") { _, _ ->
                video?.stopPlayback()
                Box.delete(f)
                Toast.makeText(this, "Deleted", Toast.LENGTH_SHORT).show()
                nextOrFinish()
            }
            .setNegativeButton("Cancel", null)
            .show()
            .getButton(AlertDialog.BUTTON_NEGATIVE)?.requestFocus()
    }

    private fun nextOrFinish() {
        if (Box.list(Box.review(this)).isNotEmpty()) show(Intent()) else finish()
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        // Play/pause key on the remote pauses the preview.
        if (keyCode == KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE || keyCode == KeyEvent.KEYCODE_MEDIA_PLAY || keyCode == KeyEvent.KEYCODE_MEDIA_PAUSE) {
            video?.let { if (it.isPlaying) it.pause() else it.start() }
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onPause() {
        video?.pause()
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        video?.start()
    }

    override fun onDestroy() {
        video?.stopPlayback()
        super.onDestroy()
    }
}
