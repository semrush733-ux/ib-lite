package com.liteplayer.recorder

import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.StateListDrawable
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/** Big, remote-friendly controls in the Lite Player colours. */
object Ui {
    val BG = Color.parseColor("#14090C")
    val CARD = Color.parseColor("#24161A")
    val RED = Color.parseColor("#E6262F")
    val DIM = Color.parseColor("#B8A9AC")
    val GOOD = Color.parseColor("#4CD07D")

    fun dp(ctx: Context, v: Int) = (v * ctx.resources.displayMetrics.density).toInt()

    private fun shape(ctx: Context, fill: Int, stroke: Int = 0) = GradientDrawable().apply {
        cornerRadius = dp(ctx, 14).toFloat()
        setColor(fill)
        if (stroke != 0) setStroke(dp(ctx, 3), stroke)
    }

    fun button(ctx: Context, text: String, primary: Boolean = false, onClick: (View) -> Unit): Button {
        val normal = if (primary) Color.parseColor("#B81E26") else CARD
        val bg = StateListDrawable().apply {
            addState(intArrayOf(android.R.attr.state_focused), shape(ctx, RED, Color.WHITE))
            addState(intArrayOf(android.R.attr.state_pressed), shape(ctx, RED, Color.WHITE))
            addState(intArrayOf(), shape(ctx, normal))
        }
        return Button(ctx).apply {
            this.text = text
            isAllCaps = false
            textSize = 19f
            setTextColor(ColorStateList.valueOf(Color.WHITE))
            background = bg
            stateListAnimator = null
            gravity = Gravity.CENTER_VERTICAL or Gravity.START
            setPadding(dp(ctx, 22), dp(ctx, 14), dp(ctx, 22), dp(ctx, 14))
            minHeight = dp(ctx, 60)
            isFocusable = true
            isFocusableInTouchMode = false
            setOnClickListener(onClick)
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
                topMargin = dp(ctx, 6)
                bottomMargin = dp(ctx, 6)
            }
        }
    }

    fun text(ctx: Context, text: String, size: Float = 16f, color: Int = DIM, bold: Boolean = false) = TextView(ctx).apply {
        this.text = text
        textSize = size
        setTextColor(color)
        if (bold) typeface = Typeface.DEFAULT_BOLD
        setLineSpacing(0f, 1.15f)
        layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
            topMargin = dp(ctx, 4)
            bottomMargin = dp(ctx, 4)
        }
    }

    fun section(ctx: Context, title: String) = text(ctx, title, 15f, RED, true).apply {
        (layoutParams as LinearLayout.LayoutParams).topMargin = dp(ctx, 22)
        letterSpacing = 0.08f
    }

    fun card(ctx: Context) = LinearLayout(ctx).apply {
        orientation = LinearLayout.VERTICAL
        background = shape(ctx, CARD)
        setPadding(dp(ctx, 18), dp(ctx, 14), dp(ctx, 18), dp(ctx, 14))
        layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
            topMargin = dp(ctx, 6)
            bottomMargin = dp(ctx, 6)
        }
    }
}
