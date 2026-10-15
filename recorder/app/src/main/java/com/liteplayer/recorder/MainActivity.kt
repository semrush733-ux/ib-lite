package com.liteplayer.recorder

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.text.InputType
import android.view.Gravity
import android.view.View
import android.view.inputmethod.EditorInfo
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast

/**
 * Main screen: Record / Screenshot, the options, and pairing with the website.
 */
class MainActivity : Activity() {

    private val REQ_REC = 1
    private val REQ_SHOT = 2
    private val REQ_AUDIO = 3

    private lateinit var prefs: Prefs
    private val main = Handler(Looper.getMainLooper())
    private var alive = false
    private var pairing = false
    private var pendingShot = false
    private var pairError = ""

    private lateinit var status: TextView
    private lateinit var btnRecord: Button
    private lateinit var btnShot: Button
    private lateinit var btnReview: Button
    private lateinit var btnUploads: Button
    private lateinit var btnQuality: Button
    private lateinit var btnFps: Button
    private lateinit var btnSound: Button
    private lateinit var btnCount: Button
    private lateinit var btnLimit: Button
    private lateinit var btnBubble: Button
    private lateinit var btnOverlay: Button
    private lateinit var siteBox: LinearLayout
    private lateinit var siteInfo: TextView
    private lateinit var siteEdit: EditText
    private lateinit var btnPair: Button
    private lateinit var codeText: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        prefs = Prefs(this)
        Notes.channels(this)
        build()
    }

    private fun build() {
        val c = this
        val col = LinearLayout(c).apply {
            orientation = LinearLayout.VERTICAL
            val w = resources.displayMetrics.widthPixels
            val side = maxOf(Ui.dp(c, 20), (w - Ui.dp(c, 760)) / 2)
            setPadding(side, Ui.dp(c, 26), side, Ui.dp(c, 40))
        }
        col.addView(Ui.text(c, "Lite Recorder", 30f, Color.WHITE, true))
        col.addView(Ui.text(c, "Record the TV screen or take screenshots for adverts. Save sends them to your website.", 15f))
        status = Ui.text(c, "", 17f, Color.WHITE, true)
        col.addView(status)

        btnRecord = Ui.button(c, "●  Record screen", true) { onRecord() }
        btnShot = Ui.button(c, "▣  Take a screenshot") { onShot() }
        btnReview = Ui.button(c, "") { startActivity(Intent(c, ReviewActivity::class.java)) }
        btnUploads = Ui.button(c, "") { UploadService.kick(c); refresh() }
        col.addView(btnRecord)
        col.addView(btnShot)
        col.addView(btnReview)
        col.addView(btnUploads)

        col.addView(Ui.section(c, "OPTIONS"))
        btnQuality = Ui.button(c, "") { prefs.quality = if (prefs.quality >= 1080) 720 else 1080; refresh() }
        btnFps = Ui.button(c, "") { prefs.fps = if (prefs.fps >= 60) 30 else 60; refresh() }
        btnSound = Ui.button(c, "") { prefs.sound = !prefs.sound; refresh() }
        btnCount = Ui.button(c, "") { prefs.countdown = next(listOf(3, 5, 10, 15), prefs.countdown); refresh() }
        btnLimit = Ui.button(c, "") { prefs.limit = next(listOf(0, 1, 2, 5, 10, 30), prefs.limit); refresh() }
        btnBubble = Ui.button(c, "") { prefs.bubble = !prefs.bubble; refresh() }
        btnOverlay = Ui.button(c, "Allow \"Display over other apps\" (opens Save / Delete by itself)") { askOverlay() }
        listOf(btnQuality, btnFps, btnSound, btnCount, btnLimit, btnBubble, btnOverlay).forEach { col.addView(it) }

        col.addView(Ui.section(c, "WEBSITE"))
        siteBox = Ui.card(c)
        siteInfo = Ui.text(c, "", 16f, Color.WHITE)
        siteEdit = EditText(c).apply {
            setText(prefs.site.ifEmpty { "https://" })
            setTextColor(Color.WHITE)
            setHintTextColor(Ui.DIM)
            hint = "https://your-website.com"
            textSize = 18f
            isSingleLine = true
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_URI
            imeOptions = EditorInfo.IME_ACTION_DONE
        }
        codeText = Ui.text(c, "", 44f, Color.WHITE, true).apply {
            gravity = Gravity.CENTER
            letterSpacing = 0.25f
            visibility = View.GONE
        }
        btnPair = Ui.button(c, "", true) { onPair() }
        siteBox.addView(siteInfo)
        siteBox.addView(siteEdit)
        siteBox.addView(codeText)
        siteBox.addView(btnPair)
        col.addView(siteBox)

        col.addView(Ui.section(c, "HOW TO"))
        col.addView(Ui.text(c,
            "1. Press Record. The TV goes back to the app you were in (or Home) and counts down.\n" +
            "2. Open Lite Player and show what you want in the advert.\n" +
            "3. To stop: open Lite Recorder again and press Stop (or set \"Stop by itself\").\n" +
            "4. Save uploads it to your website (WordPress → TV Recordings). Delete removes it.\n" +
            "Screenshot works the same way: it is taken when the countdown ends.", 15f))
        col.addView(Ui.text(c, "Version ${BuildConfig.VERSION_NAME}", 13f))

        setContentView(ScrollView(c).apply {
            setBackgroundColor(Ui.BG)
            isFillViewport = true
            addView(col)
        })
        btnRecord.requestFocus()
    }

    private fun next(list: List<Int>, cur: Int): Int = list[(list.indexOf(cur) + 1).mod(list.size)]

    override fun onResume() {
        super.onResume()
        alive = true
        Box.clean(this)
        UploadService.kick(this)
        loop()
        // Something new to check: straight to Save / Delete.
        if (CaptureService.state.isEmpty() && Box.list(Box.review(this)).isNotEmpty() && intent?.getBooleanExtra("noReview", false) != true) {
            btnReview.requestFocus()
        } else if (CaptureService.state == "recording") {
            btnRecord.requestFocus()
        }
    }

    override fun onPause() {
        alive = false
        super.onPause()
    }

    override fun onDestroy() {
        pairing = false
        super.onDestroy()
    }

    private fun loop() {
        if (!alive) return
        refresh()
        main.postDelayed({ loop() }, 1000)
    }

    private fun refresh() {
        val st = CaptureService.state
        btnRecord.text = when (st) {
            "recording" -> if (CaptureService.startedAt > 0) "■  Stop recording   " + fmtTime((System.currentTimeMillis() - CaptureService.startedAt) / 1000) else "■  Stop"
            "countdown" -> "■  Cancel (starts in ${CaptureService.countdownLeft + 1})"
            "saving" -> "Saving the recording…"
            else -> "●  Record screen"
        }
        btnShot.visibility = if (st.isEmpty()) View.VISIBLE else View.GONE
        status.text = when {
            st == "recording" -> "● Recording…  Open Lite Recorder and press Stop when done."
            CaptureService.lastError.isNotEmpty() -> CaptureService.lastError
            else -> ""
        }
        status.setTextColor(if (st == "recording") Ui.RED else Color.WHITE)
        status.visibility = if (status.text.isEmpty()) View.GONE else View.VISIBLE

        val review = Box.list(Box.review(this)).size
        btnReview.visibility = if (review > 0 && st.isEmpty()) View.VISIBLE else View.GONE
        btnReview.text = "✓  $review waiting for Save / Delete — open"

        val out = Box.list(Box.outbox(this)).size
        btnUploads.visibility = if (out > 0 || UploadService.running) View.VISIBLE else View.GONE
        btnUploads.text = when {
            UploadService.running -> "↑  Uploading ${UploadService.percent}%  ($out left)"
            !prefs.paired -> "↑  $out saved — pair with the website below to upload"
            else -> "↑  $out waiting to upload — try again" + (if (prefs.lastError.isNotEmpty()) "\n   ${prefs.lastError}" else "")
        }

        btnQuality.text = "Quality:  " + if (prefs.quality >= 1080) "1080p (sharpest)" else "720p (smaller files, weak boxes)"
        btnFps.text = "Smoothness:  " + if (prefs.fps >= 60) "60 fps (very smooth, bigger files)" else "30 fps (smooth)"
        btnSound.text = "Sound:  " + when {
            Build.VERSION.SDK_INT < 29 -> "not possible on this TV (Android 10+ needed)"
            prefs.sound -> "On (the sound of the apps, not the microphone)"
            else -> "Off"
        }
        btnCount.text = "Countdown:  ${prefs.countdown} seconds"
        btnLimit.text = "Stop by itself:  " + if (prefs.limit == 0) "Never (press Stop)" else "after ${prefs.limit} min"
        btnBubble.text = "REC timer on screen:  " + if (prefs.bubble) "On (also in the video)" else "Off (clean video)"
        btnOverlay.visibility = if (Build.VERSION.SDK_INT >= 23 && !Settings.canDrawOverlays(this)) View.VISIBLE else View.GONE

        if (!pairing) {
            codeText.visibility = View.GONE
            if (prefs.paired) {
                siteInfo.text = "✓ Connected to ${prefs.siteName.ifEmpty { prefs.site }}\n${prefs.site}" +
                    (if (prefs.uploadedCount > 0) "\n${prefs.uploadedCount} files uploaded" else "")
                siteInfo.setTextColor(Ui.GOOD)
                siteEdit.visibility = View.GONE
                btnPair.text = "Pair again / other website"
            } else {
                siteInfo.text = pairError.ifEmpty { "Not connected. Type the website address, press Pair, then type the code in WordPress → TV Recordings." }
                siteInfo.setTextColor(if (pairError.isEmpty()) Color.WHITE else Ui.RED)
                siteEdit.visibility = View.VISIBLE
                btnPair.text = "Pair with website"
            }
        }
    }

    // ------------------------------------------------------------------ capture

    private fun onRecord() {
        when (CaptureService.state) {
            "recording", "countdown" -> {
                CaptureService.stop(this)
                return
            }
            "saving" -> return
        }
        pendingShot = false
        if (prefs.sound && Build.VERSION.SDK_INT >= 29 && checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(android.Manifest.permission.RECORD_AUDIO), REQ_AUDIO)
            return
        }
        ask(REQ_REC)
    }

    private fun onShot() {
        if (CaptureService.state.isNotEmpty()) return
        pendingShot = true
        ask(REQ_SHOT)
    }

    private fun ask(req: Int) {
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 9)
        }
        CaptureService.lastError = ""
        val mpm = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        try {
            startActivityForResult(mpm.createScreenCaptureIntent(), req)
        } catch (e: Exception) {
            toast("This TV does not offer screen capture.")
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_AUDIO) {
            if (grantResults.firstOrNull() != PackageManager.PERMISSION_GRANTED) toast("Recording without sound.")
            ask(REQ_REC)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_REC && requestCode != REQ_SHOT) return
        if (resultCode != RESULT_OK || data == null) {
            toast("Screen capture was not allowed.")
            return
        }
        val i = Intent(this, CaptureService::class.java)
            .setAction(CaptureService.ACTION_START)
            .putExtra(CaptureService.EXTRA_CODE, resultCode)
            .putExtra(CaptureService.EXTRA_DATA, data)
            .putExtra(CaptureService.EXTRA_SHOT, requestCode == REQ_SHOT)
        try {
            if (Build.VERSION.SDK_INT >= 26) startForegroundService(i) else startService(i)
        } catch (e: Exception) {
            toast("Could not start: ${e.message}")
            return
        }
        // Back to the app the viewer came from (e.g. Lite Player) while the countdown runs.
        moveTaskToBack(true)
    }

    private fun askOverlay() {
        if (Build.VERSION.SDK_INT < 23) return
        try {
            startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")))
        } catch (_: Exception) {
            try {
                startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION))
            } catch (_: Exception) {
                toast("This TV has no such setting. Open Lite Recorder after recording to Save / Delete.")
            }
        }
    }

    // ------------------------------------------------------------------ pairing

    private fun onPair() {
        if (pairing) {
            pairing = false
            refresh()
            return
        }
        if (prefs.paired && siteEdit.visibility == View.GONE) {
            siteEdit.visibility = View.VISIBLE
            siteEdit.setText(prefs.site)
            siteInfo.text = "Type the website address, then press Pair."
            siteInfo.setTextColor(Color.WHITE)
            btnPair.text = "Pair with website"
            prefs.token = ""
            siteEdit.requestFocus()
            return
        }
        var site = siteEdit.text.toString().trim().trimEnd('/')
        if (site.isEmpty() || site == "https:" || site == "http:") {
            toast("Type your website address first.")
            siteEdit.requestFocus()
            return
        }
        if (!site.startsWith("http://") && !site.startsWith("https://")) site = "https://$site"
        siteEdit.setText(site)
        pairing = true
        pairError = ""
        siteInfo.text = "Asking $site for a code…"
        siteInfo.setTextColor(Color.WHITE)
        btnPair.text = "Cancel"
        val name = (Build.MANUFACTURER + " " + Build.MODEL).trim()
        Thread {
            try {
                val r = Net(site).post("pair/start", mapOf("name" to name.take(40), "model" to name))
                val code = r.getString("code")
                val poll = r.getString("poll")
                main.post {
                    codeText.text = code.substring(0, 3) + " " + code.substring(3)
                    codeText.visibility = View.VISIBLE
                    siteInfo.text = "On the website: WordPress → TV Recordings → type this code → Pair."
                }
                val until = System.currentTimeMillis() + 15 * 60 * 1000
                while (pairing && System.currentTimeMillis() < until) {
                    Thread.sleep(3000)
                    val p = try {
                        Net(site).post("pair/poll", mapOf("code" to code, "poll" to poll))
                    } catch (e: ApiError) {
                        if (e.status == 404) throw e else continue
                    } catch (_: Exception) {
                        continue
                    }
                    if (p.optBoolean("paired")) {
                        prefs.site = site
                        prefs.token = p.getString("token")
                        prefs.siteName = p.optString("site")
                        main.post {
                            pairing = false
                            toast("Connected to ${prefs.siteName.ifEmpty { site }}")
                            UploadService.kick(this)
                            refresh()
                            btnRecord.requestFocus()
                        }
                        return@Thread
                    }
                }
                main.post {
                    if (pairing) toast("The code expired. Press Pair again.")
                    pairing = false
                    refresh()
                }
            } catch (e: Exception) {
                main.post {
                    pairing = false
                    pairError = "Could not pair: ${e.message}"
                    refresh()
                }
            }
        }.start()
    }

    private fun toast(s: String) = Toast.makeText(this, s, Toast.LENGTH_LONG).show()
}
