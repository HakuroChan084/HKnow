package com.hknow.app

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Shader
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.animation.AccelerateDecelerateInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import kotlin.math.cos
import kotlin.math.sin
import kotlin.random.Random

/** Hoa đào rơi, vẽ bằng Canvas (không nhận chạm). */
class SakuraView(context: Context, private val count: Int = 36) : View(context) {
    private class Petal(var x: Float, var y: Float, var size: Float, var speed: Float,
                        var sway: Float, var phase: Float, var rot: Float, var spin: Float, var color: Int)

    private val colors = intArrayOf(0xFFFFC7DD.toInt(), 0xFFFFA6C9.toInt(), 0xFFFFE0EC.toInt())
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val path = Path().apply {
        moveTo(0f, 1f)
        cubicTo(-0.9f, 0.7f, -1.2f, -0.3f, -0.6f, -0.9f)
        lineTo(0f, -0.6f)
        lineTo(0.6f, -0.9f)
        cubicTo(1.2f, -0.3f, 0.9f, 0.7f, 0f, 1f)
        close()
    }
    private var petals = emptyList<Petal>()
    private var last = 0L
    private val d = resources.displayMetrics.density

    init { isClickable = false; isFocusable = false }

    private fun spawn(w: Int, h: Int, anywhere: Boolean) = Petal(
        x = Random.nextFloat() * w * 1.2f - w * 0.1f,
        y = if (anywhere) Random.nextFloat() * h else -20f * d,
        size = (5f + Random.nextFloat() * 6f) * d,
        speed = (35f + Random.nextFloat() * 45f) * d,
        sway = (12f + Random.nextFloat() * 22f) * d,
        phase = Random.nextFloat() * 6.28f,
        rot = Random.nextFloat() * 360f,
        spin = -80f + Random.nextFloat() * 160f,
        color = colors[Random.nextInt(colors.size)],
    )

    override fun onSizeChanged(w: Int, h: Int, ow: Int, oh: Int) {
        petals = List(count) { spawn(w, h, true) }
    }

    override fun onDraw(c: Canvas) {
        val now = System.nanoTime()
        val dt = if (last == 0L) 0.016f else ((now - last) / 1e9f).coerceAtMost(0.05f)
        last = now
        for (p in petals) {
            p.y += p.speed * dt
            p.phase += dt * 1.4f
            p.x += (sin(p.phase) * p.sway + 14f * d) * dt
            p.rot += p.spin * dt
            if (p.y > height + 30 * d || p.x > width + 40 * d) {
                val n = spawn(width, height, false)
                p.x = n.x; p.y = n.y; p.size = n.size; p.speed = n.speed; p.sway = n.sway; p.color = n.color
            }
            paint.color = p.color
            paint.alpha = 215
            c.save()
            c.translate(p.x, p.y)
            c.rotate(p.rot)
            // lật nhẹ theo phase để trông như cánh hoa xoay trong gió
            c.scale(p.size * (0.55f + 0.45f * cos(p.phase)), p.size)
            c.drawPath(path, paint)
            c.restore()
        }
        postInvalidateOnAnimation()
    }
}

/** Màn hình mở đầu: ảnh nhân vật + hoa đào rơi, tự mờ dần (chạm để bỏ qua). */
class SplashLayer(context: Context, private val onDone: (SplashLayer) -> Unit) : FrameLayout(context) {
    private var finished = false

    init {
        setBackgroundColor(0xFF2B1020.toInt())
        addView(ImageView(context).apply {
            setImageResource(R.drawable.waifu)
            scaleType = ImageView.ScaleType.CENTER_CROP
        }, LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))

        // Lớp phủ hồng ở phần dưới cho chữ dễ đọc
        addView(View(context).apply {
            background = GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM,
                intArrayOf(0x00000000, 0xC0731A47.toInt())).apply { }
        }, LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))

        addView(SakuraView(context, 70), LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))

        val d = resources.displayMetrics.density
        addView(TextView(context).apply {
            text = "HKnow  ♡"
            textSize = 30f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            setTypeface(typeface, android.graphics.Typeface.BOLD)
            setShadowLayer(14f, 0f, 0f, 0xFFE63B88.toInt())
        }, LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, (56 * d).toInt()).apply {
            gravity = Gravity.BOTTOM
            bottomMargin = (28 * d).toInt()
        })

        alpha = 0f
        animate().alpha(1f).setDuration(500).start()
        postDelayed({ dismiss() }, 3600)
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (event.action == MotionEvent.ACTION_DOWN) dismiss()
        return true     // chặn chạm xuyên xuống game khi đang hiện
    }

    private fun dismiss() {
        if (finished) return
        finished = true
        animate().alpha(0f).setDuration(800).setInterpolator(AccelerateDecelerateInterpolator())
            .withEndAction { onDone(this) }.start()
    }
}
