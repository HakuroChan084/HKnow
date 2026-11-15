package com.hknow.app

import android.content.Context
import android.graphics.Canvas
import android.graphics.DashPathEffect
import android.graphics.Paint
import android.graphics.RectF
import android.os.Handler
import android.os.Looper
import android.view.MotionEvent
import android.view.View
import kotlin.math.abs
import kotlin.math.hypot

/**
 * Lớp điều khiển phủ lên WebView.
 * Đang chơi: CHỈ nhận chạm ở nút tròn, joystick và vùng xoay camera (vùng này trong suốt 100%).
 * Mọi chỗ trống còn lại: onTouchEvent trả false => chạm đi xuyên xuống WebView (bấm menu / chọn súng / Settings).
 */
class OverlayView(context: Context) : View(context) {

    var onLook: ((Float, Float) -> Unit)? = null
    var onAction: ((PadAction, Boolean) -> Unit)? = null
    /** Joystick đã chuẩn hóa: x, y trong [-1, 1], y dương = kéo xuống */
    var onJoystick: ((Float, Float) -> Unit)? = null
    var onEditButton: ((String) -> Unit)? = null
    var onEditJoystick: (() -> Unit)? = null
    var onEditLook: (() -> Unit)? = null
    /** Nhấn giữ chỗ trống khi chỉnh sửa: toạ độ pixel */
    var onLongPressEmpty: ((Float, Float) -> Unit)? = null

    /** Chế độ "Chạm = chuột": kéo = di chuyển con trỏ trong game, chạm nhanh = click trái */
    var onPointerMove: ((Float, Float) -> Unit)? = null
    var onPointerClick: (() -> Unit)? = null

    /** true = vùng trống ngoài nút / joystick / vùng xoay camera hoạt động như touchpad chuột */
    var touchpadActive = false
        set(v) {
            if (field == v) return
            field = v
            reset(true)
        }

    var aimHeld = false
        private set

    var hudHidden = false
        set(v) {
            if (field == v) return
            field = v
            reset(true)
            invalidate()
        }

    var editing = false
        set(v) {
            if (field == v) return
            field = v
            if (v) hudHidden = false
            reset(true)
            reload()
        }

    private sealed class Role {
        object Look : Role()
        object Joystick : Role()
        data class Button(val id: String) : Role()
        data class EditButton(val id: String) : Role()
        object EditJoystick : Role()
        object EditLook : Role()
        object Pointer : Role()
        object None : Role()
    }

    private val d = resources.displayMetrics.density
    private val roles = HashMap<Int, Role>()
    private val last = HashMap<Int, FloatArray>()
    private val start = HashMap<Int, FloatArray>()
    private val dragged = HashSet<Int>()
    private val pressed = HashSet<String>()
    private val downTimes = HashMap<Int, Long>()
    private var joyOffX = 0f
    private var joyOffY = 0f
    private var heldJoy = HashSet<String>()

    private val joyKeys = mapOf("KeyW" to KeySpec.W, "KeyA" to KeySpec.A, "KeyS" to KeySpec.S, "KeyD" to KeySpec.D)

    private val handler = Handler(Looper.getMainLooper())
    private var longPressRunnable: Runnable? = null

    private val fill = Paint(Paint.ANTI_ALIAS_FLAG)
    private val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeWidth = 2f * d }
    private val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0xFFFFFFFF.toInt(); textAlign = Paint.Align.CENTER; isFakeBoldText = true
    }
    private val dashed = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE; strokeWidth = 2f * d; color = 0xFFFFCC00.toInt()
        pathEffect = DashPathEffect(floatArrayOf(8f * d, 6f * d), 0f)
    }

    private val settings get() = PadStore.settings

    fun reload() {
        alpha = if (editing) 1f else settings.opacity
        invalidate()
    }

    // ---------- Hình học ----------

    private fun lookRect(): RectF {
        val s = settings
        val w = s.lookWidth * width
        val h = s.lookHeight * height
        return RectF(s.lookX * width - w / 2, s.lookY * height - h / 2, s.lookX * width + w / 2, s.lookY * height + h / 2)
    }

    private fun visible(b: PadButton) = !(hudHidden && b.action != PadAction.ToggleHud)

    private fun buttonAt(x: Float, y: Float): PadButton? {
        for (b in settings.buttons.asReversed()) {
            if (!visible(b)) continue
            if (hypot(x - b.x * width, y - b.y * height) <= b.size * d / 2) return b
        }
        return null
    }

    private fun joyCenterX() = settings.joyX * width
    private fun joyCenterY() = settings.joyY * height
    private fun joyRadius() = settings.joySize * d / 2

    private fun joystickHit(x: Float, y: Float) =
        !hudHidden && hypot(x - joyCenterX(), y - joyCenterY()) <= joyRadius()

    // ---------- Vẽ ----------

    override fun onDraw(c: Canvas) {
        // Vùng xoay camera: chỉ hiện khi chỉnh sửa, lúc chơi trong suốt 100%
        if (editing) {
            val r = lookRect()
            fill.color = 0x14FFCC00
            c.drawRoundRect(r, 14f * d, 14f * d, fill)
            c.drawRoundRect(r, 14f * d, 14f * d, dashed)
            text.color = 0x8CFFFFFF.toInt(); text.textSize = 16f * d
            c.drawText("Vùng xoay camera", r.centerX(), r.centerY() + 6f * d, text)
        }

        if (!hudHidden) {
            // Joystick
            val cx = joyCenterX(); val cy = joyCenterY(); val r = joyRadius()
            fill.color = 0x1AFFFFFF
            c.drawCircle(cx, cy, r, fill)
            stroke.color = if (editing) 0xFFFFCC00.toInt() else 0x99FFFFFF.toInt()
            c.drawCircle(cx, cy, r, stroke)
            fill.color = 0x73FFFFFF
            c.drawCircle(cx + joyOffX, cy + joyOffY, r * 0.42f, fill)
        }

        // Nút tròn
        for (b in settings.buttons) {
            if (!visible(b)) continue
            val cx = b.x * width; val cy = b.y * height; val r = b.size * d / 2
            fill.color = if (b.id in pressed) 0x80FFFFFF.toInt() else 0x29FFFFFF
            c.drawCircle(cx, cy, r, fill)
            stroke.color = if (editing) 0xFFFFCC00.toInt() else 0xBFFFFFFF.toInt()
            c.drawCircle(cx, cy, r, stroke)
            text.color = 0xFFFFFFFF.toInt()
            text.textSize = (if (b.label.length > 4) 11f else 15f) * d * (b.size / 64f).coerceIn(0.8f, 1.4f)
            c.drawText(b.label, cx, cy + text.textSize / 3, text)
        }

        if (editing) {
            text.color = 0xFFFFCC00.toInt(); text.textSize = 14f * d
            c.drawText(
                "Chỉnh sửa: kéo để di chuyển • chạm nút / khung vàng để sửa • nhấn giữ chỗ trống để thêm nút",
                width / 2f, 76f * d, text
            )
        }
    }

    // ---------- Cảm ứng ----------

    override fun onTouchEvent(e: MotionEvent): Boolean {
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                val i = e.actionIndex
                val claimed = down(e.getPointerId(i), e.getX(i), e.getY(i))
                // Chỉ trả false khi chưa giữ ngón nào và chạm vào vùng trống => cho WebView nhận chạm
                return claimed || roles.isNotEmpty()
            }
            MotionEvent.ACTION_MOVE -> {
                for (i in 0 until e.pointerCount) move(e.getPointerId(i), e.getX(i), e.getY(i))
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP -> {
                val i = e.actionIndex
                finish(e.getPointerId(i), false)
            }
            MotionEvent.ACTION_CANCEL -> {
                for (id in roles.keys.toList()) finish(id, true)
            }
        }
        return roles.isNotEmpty()
    }

    /** true = overlay nhận ngón này; false = để chạm xuyên xuống WebView */
    private fun down(id: Int, x: Float, y: Float): Boolean {
        if (hudHidden && !editing) {
            val b = buttonAt(x, y) ?: return false
            press(id, b)
            return true
        }
        start[id] = floatArrayOf(x, y)
        last[id] = floatArrayOf(x, y)

        if (editing) {
            val b = buttonAt(x, y)
            when {
                b != null -> roles[id] = Role.EditButton(b.id)
                joystickHit(x, y) -> roles[id] = Role.EditJoystick
                lookRect().contains(x, y) -> roles[id] = Role.EditLook
                else -> {
                    roles[id] = Role.None
                    val r = Runnable {
                        if (roles[id] == Role.None && id !in dragged) {
                            performHapticFeedback(android.view.HapticFeedbackConstants.LONG_PRESS)
                            onLongPressEmpty?.invoke(x, y)
                        }
                    }
                    longPressRunnable = r
                    handler.postDelayed(r, 500)
                }
            }
            return true
        }

        val b = buttonAt(x, y)
        when {
            b != null -> press(id, b)
            joystickHit(x, y) -> { roles[id] = Role.Joystick; moveJoystick(x, y) }
            lookRect().contains(x, y) -> roles[id] = Role.Look      // CHỈ để vuốt, tap không thành click
            touchpadActive -> { roles[id] = Role.Pointer; downTimes[id] = android.os.SystemClock.uptimeMillis() }
            else -> { start.remove(id); last.remove(id); return false }
        }
        return true
    }

    private fun press(id: Int, b: PadButton) {
        roles[id] = Role.Button(b.id)
        pressed.add(b.id)
        recomputeAim()
        onAction?.invoke(b.action, true)
        invalidate()
    }

    private fun move(id: Int, x: Float, y: Float) {
        val role = roles[id] ?: return
        val prev = last[id] ?: floatArrayOf(x, y)
        val s = start[id] ?: floatArrayOf(x, y)
        val dx = x - prev[0]; val dy = y - prev[1]
        last[id] = floatArrayOf(x, y)
        if (hypot(x - s[0], y - s[1]) > 8f * d) dragged.add(id)
        if (id in dragged) cancelAddPress()

        when (role) {
            Role.Look -> onLook?.invoke(dx / d, dy / d)
            Role.Pointer -> onPointerMove?.invoke(dx / d, dy / d)
            Role.Joystick -> moveJoystick(x, y)
            is Role.Button, Role.None -> {}
            is Role.EditButton -> {
                if (id !in dragged || width == 0 || height == 0) return
                settings.buttons.firstOrNull { it.id == role.id }?.let {
                    it.x = (it.x + dx / width).coerceIn(0.03f, 0.97f)
                    it.y = (it.y + dy / height).coerceIn(0.05f, 0.95f)
                }
                invalidate()
            }
            Role.EditJoystick -> {
                if (id !in dragged || width == 0 || height == 0) return
                settings.joyX = (settings.joyX + dx / width).coerceIn(0.05f, 0.95f)
                settings.joyY = (settings.joyY + dy / height).coerceIn(0.08f, 0.95f)
                invalidate()
            }
            Role.EditLook -> {
                if (id !in dragged || width == 0 || height == 0) return
                settings.lookX += dx / width
                settings.lookY += dy / height
                settings.clampLookPad()
                invalidate()
            }
        }
    }

    private fun finish(id: Int, cancelled: Boolean) {
        cancelAddPress()
        val role = roles.remove(id) ?: return
        val wasDragged = id in dragged
        dragged.remove(id); start.remove(id); last.remove(id)
        when (role) {
            Role.Look, Role.None -> {}
            Role.Pointer -> {
                val t0 = downTimes.remove(id)
                // Chạm nhanh, gần như không di chuyển = click trái
                if (!cancelled && !wasDragged && t0 != null && android.os.SystemClock.uptimeMillis() - t0 < 300) onPointerClick?.invoke()
            }
            Role.Joystick -> {
                joyOffX = 0f; joyOffY = 0f
                onJoystick?.invoke(0f, 0f)
                updateJoystickKeys()
            }
            is Role.Button -> {
                pressed.remove(role.id)
                settings.buttons.firstOrNull { it.id == role.id }?.let { onAction?.invoke(it.action, false) }
                recomputeAim()
            }
            is Role.EditButton -> {
                PadStore.save()
                if (!wasDragged && !cancelled) onEditButton?.invoke(role.id)
            }
            Role.EditJoystick -> {
                PadStore.save()
                if (!wasDragged && !cancelled) onEditJoystick?.invoke()
            }
            Role.EditLook -> {
                PadStore.save()
                if (!wasDragged && !cancelled) onEditLook?.invoke()
            }
        }
        invalidate()
    }

    private fun cancelAddPress() {
        longPressRunnable?.let { handler.removeCallbacks(it) }
        longPressRunnable = null
    }

    private fun recomputeAim() {
        aimHeld = roles.values.any { r ->
            r is Role.Button && settings.buttons.firstOrNull { it.id == r.id }?.action?.isAim == true
        }
    }

    // ---------- Joystick ----------

    private fun moveJoystick(x: Float, y: Float) {
        val dx = x - joyCenterX(); val dy = y - joyCenterY()
        val r = joyRadius()
        val len = hypot(dx, dy)
        val k = if (len > r) r / len else 1f
        joyOffX = dx * k; joyOffY = dy * k
        onJoystick?.invoke(joyOffX / maxOf(r, 1f), joyOffY / maxOf(r, 1f))
        updateJoystickKeys()
        invalidate()
    }

    private fun updateJoystickKeys() {
        val r = maxOf(joyRadius(), 1f)
        val nx = joyOffX / r; val ny = joyOffY / r
        val want = HashSet<String>()
        if (ny < -0.35f) want.add("KeyW")
        if (ny > 0.35f) want.add("KeyS")
        if (nx < -0.35f) want.add("KeyA")
        if (nx > 0.35f) want.add("KeyD")
        for (c in want - heldJoy) joyKeys[c]?.let { onAction?.invoke(PadAction.Key(it), true) }
        for (c in heldJoy - want) joyKeys[c]?.let { onAction?.invoke(PadAction.Key(it), false) }
        heldJoy = want
    }

    /** Nhả mọi nút / phím đang giữ */
    fun reset(notify: Boolean) {
        cancelAddPress()
        if (notify) {
            for (c in heldJoy) joyKeys[c]?.let { onAction?.invoke(PadAction.Key(it), false) }
            for (r in roles.values) {
                if (r is Role.Button) settings.buttons.firstOrNull { it.id == r.id }?.let { onAction?.invoke(it.action, false) }
            }
        }
        downTimes.clear(); heldJoy.clear(); roles.clear(); last.clear(); start.clear(); dragged.clear(); pressed.clear()
        aimHeld = false
        joyOffX = 0f; joyOffY = 0f
        if (notify) onJoystick?.invoke(0f, 0f)
        invalidate()
    }
}
