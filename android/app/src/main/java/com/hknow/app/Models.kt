package com.hknow.app

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

// ---------- Phím bàn phím ----------

data class KeySpec(val key: String, val code: String, val keyCode: Int) {
    val display: String
        get() = when (code) {
            "Space" -> "Space"
            "ShiftLeft" -> "L-Shift"
            "ShiftRight" -> "R-Shift"
            "ControlLeft" -> "L-Ctrl"
            "ControlRight" -> "R-Ctrl"
            "AltLeft" -> "L-Alt"
            "AltRight" -> "R-Alt"
            "Escape" -> "Esc"
            "Backspace" -> "Bksp"
            "CapsLock" -> "Caps"
            "ArrowUp" -> "↑"
            "ArrowDown" -> "↓"
            "ArrowLeft" -> "←"
            "ArrowRight" -> "→"
            else -> key.uppercase()
        }

    companion object {
        val W = KeySpec("w", "KeyW", 87)
        val A = KeySpec("a", "KeyA", 65)
        val S = KeySpec("s", "KeyS", 83)
        val D = KeySpec("d", "KeyD", 68)
        val SPACE = KeySpec(" ", "Space", 32)
        val SHIFT = KeySpec("Shift", "ShiftLeft", 16)
        val SHIFT_R = KeySpec("Shift", "ShiftRight", 16)
        val CTRL = KeySpec("Control", "ControlLeft", 17)
        val CTRL_R = KeySpec("Control", "ControlRight", 17)
        val ALT = KeySpec("Alt", "AltLeft", 18)
        val ALT_R = KeySpec("Alt", "AltRight", 18)
        val TAB = KeySpec("Tab", "Tab", 9)
        val ENTER = KeySpec("Enter", "Enter", 13)
        val ESC = KeySpec("Escape", "Escape", 27)
        val BACKSPACE = KeySpec("Backspace", "Backspace", 8)
        val CAPS = KeySpec("CapsLock", "CapsLock", 20)
        val UP = KeySpec("ArrowUp", "ArrowUp", 38)
        val DOWN = KeySpec("ArrowDown", "ArrowDown", 40)
        val LEFT = KeySpec("ArrowLeft", "ArrowLeft", 37)
        val RIGHT = KeySpec("ArrowRight", "ArrowRight", 39)

        val modifiers = listOf(SHIFT, SHIFT_R, CTRL, CTRL_R, ALT, ALT_R)
        val controls = listOf(ENTER, ESC, SPACE, TAB, BACKSPACE, CAPS)
        val functionKeys = (1..12).map { KeySpec("F$it", "F$it", 111 + it) }
        val arrows = listOf(UP, DOWN, LEFT, RIGHT)
        val letters = (65..90).map { v ->
            val c = v.toChar().toString()
            KeySpec(c.lowercase(), "Key$c", v)
        }
        val digits = (0..9).map { KeySpec("$it", "Digit$it", 48 + it) }
        val punctuation = listOf(
            KeySpec("-", "Minus", 189), KeySpec("=", "Equal", 187),
            KeySpec("[", "BracketLeft", 219), KeySpec("]", "BracketRight", 221),
            KeySpec(";", "Semicolon", 186), KeySpec("'", "Quote", 222),
            KeySpec(",", "Comma", 188), KeySpec(".", "Period", 190),
            KeySpec("/", "Slash", 191), KeySpec("`", "Backquote", 192),
            KeySpec("\\", "Backslash", 220),
        )
        val all = modifiers + controls + functionKeys + arrows + letters + digits + punctuation

        fun parse(raw: String): KeySpec? {
            val u = raw.trim().uppercase()
            if (u.isEmpty()) return null
            when (u) {
                "SPACE" -> return SPACE
                "ENTER", "RETURN" -> return ENTER
                "ESC", "ESCAPE" -> return ESC
                "UP" -> return UP
                "DOWN" -> return DOWN
                "LEFT" -> return LEFT
                "RIGHT" -> return RIGHT
                "BACKSPACE", "BKSP" -> return BACKSPACE
                "CAPS", "CAPSLOCK" -> return CAPS
            }
            return all.firstOrNull {
                it.code.uppercase() == u || it.key.uppercase() == u || it.display.uppercase() == u
            }
        }
    }
}

// ---------- Nút tay cầm Xbox (chỉ số theo mapping "standard") ----------

object GamepadButton {
    const val LT = 6
}

// ---------- Hành động của một nút ----------

sealed class PadAction {
    data class Mouse(val button: Int) : PadAction()        // 0 = trái (RT), 1 = giữa (R3), 2 = phải (LT)
    data class Key(val spec: KeySpec) : PadAction()
    object ReleaseLock : PadAction()
    data class Pad(val index: Int) : PadAction()           // nút tay cầm ảo (LB, RB, A, B, X, Y, ...)
    object ToggleKeyboard : PadAction()
    object ToggleHud : PadAction()

    val title: String
        get() = when (this) {
            is Mouse -> when (button) {
                0 -> "Bắn (RT / Chuột trái)"
                2 -> "Ngắm (LT / Chuột phải)"
                else -> "R3 (Chuột giữa)"
            }
            is Key -> "Phím " + spec.display
            ReleaseLock -> "Thả chuột (mở menu)"
            is Pad -> "Tay cầm: " + padShort(index)
            ToggleKeyboard -> "Bật/Tắt bàn phím ảo"
            ToggleHud -> "Ẩn/Hiện HUD"
        }

    val defaultLabel: String
        get() = when (this) {
            is Mouse -> when (button) { 0 -> "Bắn"; 2 -> "Ngắm"; else -> "R3" }
            is Key -> spec.display
            ReleaseLock -> "Menu"
            is Pad -> padShort(index)
            ToggleKeyboard -> "⌨"
            ToggleHud -> "HUD"
        }

    /** Đang giữ nút Ngắm (LT / chuột phải): dùng cho gyro "chỉ khi ngắm" */
    val isAim: Boolean
        get() = when (this) {
            is Mouse -> button == 2
            is Pad -> index == GamepadButton.LT
            else -> false
        }

    fun toJson(): JSONObject = when (this) {
        is Mouse -> JSONObject().put("t", "mouse").put("v", button)
        is Key -> JSONObject().put("t", "key").put("key", spec.key).put("code", spec.code).put("kc", spec.keyCode)
        ReleaseLock -> JSONObject().put("t", "release")
        is Pad -> JSONObject().put("t", "pad").put("v", index)
        ToggleKeyboard -> JSONObject().put("t", "kbd")
        ToggleHud -> JSONObject().put("t", "hud")
    }

    companion object {
        fun padShort(i: Int): String = when (i) {
            0 -> "A"; 1 -> "B"; 2 -> "X"; 3 -> "Y"; 4 -> "LB"; 5 -> "RB"; 6 -> "LT"; 7 -> "RT"
            8 -> "Back"; 9 -> "Start"; 10 -> "L3"; 11 -> "R3"
            12 -> "D↑"; 13 -> "D↓"; 14 -> "D←"; 15 -> "D→"
            else -> "$i"
        }

        fun fromJson(o: JSONObject): PadAction? = when (o.optString("t")) {
            "mouse" -> Mouse(o.optInt("v"))
            "key" -> Key(KeySpec(o.optString("key"), o.optString("code"), o.optInt("kc")))
            "release" -> ReleaseLock
            "pad" -> Pad(o.optInt("v"))
            "kbd" -> ToggleKeyboard
            "hud" -> ToggleHud
            else -> null
        }

        /** Danh sách hành động hay dùng (hiện ngay ở bảng chọn đầu tiên) */
        val presets: List<Pair<String, PadAction>> by lazy {
            val list = mutableListOf<Pair<String, PadAction>>(
                "Chuột trái (bắn)" to Mouse(0), "Chuột phải (ngắm)" to Mouse(2), "Chuột giữa" to Mouse(1),
                "Space (nhảy)" to Key(KeySpec.SPACE), "Shift (chạy)" to Key(KeySpec.SHIFT), "Ctrl (ngồi)" to Key(KeySpec.CTRL),
            )
            for (ch in listOf("R", "E", "F", "Q", "C", "V", "G", "X", "Z")) {
                KeySpec.parse(ch)?.let { list.add("Phím $ch" to Key(it)) }
            }
            list.add("Tab" to Key(KeySpec.TAB)); list.add("Alt" to Key(KeySpec.ALT))
            for (n in 1..5) KeySpec.parse("$n")?.let { list.add("Phím $n" to Key(it)) }
            list.add("Bật/Tắt bàn phím ảo" to ToggleKeyboard)
            list.add("Ẩn/Hiện HUD" to ToggleHud)
            list.add("Thả chuột (mở menu GFN)" to ReleaseLock)
            list
        }

        /** Bảng chọn: (tên nhóm, danh sách (nhãn, hành động)) */
        val catalog: List<Pair<String, List<Pair<String, PadAction>>>> by lazy {
            fun k(s: KeySpec) = s.display to (Key(s) as PadAction)
            fun p(i: Int, label: String) = label to (Pad(i) as PadAction)
            listOf(
                "Tay cầm / Bắn" to listOf(
                    "Bắn" to Mouse(0), "Ngắm" to Mouse(2), "R3" to Mouse(1),
                    p(4, "LB"), p(5, "RB"), p(0, "A"), p(1, "B"), p(2, "X"), p(3, "Y"),
                    p(10, "L3"), p(9, "Start"), p(8, "Back"),
                    p(12, "D-Pad ↑"), p(13, "D-Pad ↓"), p(14, "D-Pad ←"), p(15, "D-Pad →"),
                ),
                "Phím bổ trợ (Trái / Phải)" to KeySpec.modifiers.map { k(it) },
                "Phím điều khiển" to KeySpec.controls.map { k(it) },
                "Phím chức năng" to KeySpec.functionKeys.map { k(it) },
                "Phím mũi tên" to KeySpec.arrows.map { k(it) },
                "Chữ cái A – Z" to KeySpec.letters.map { k(it) },
                "Số & dấu câu" to (KeySpec.digits + KeySpec.punctuation).map { k(it) },
                "Hệ thống" to listOf(
                    "Bàn phím ảo" to ToggleKeyboard, "Ẩn/Hiện HUD" to ToggleHud, "Thả chuột" to ReleaseLock,
                ),
            )
        }
    }
}

// ---------- Nút bấm & cài đặt ----------

data class PadButton(
    val id: String = UUID.randomUUID().toString(),
    var label: String,
    var action: PadAction,
    var x: Float,        // tâm nút, 0..1 theo chiều ngang màn hình
    var y: Float,        // 0..1 theo chiều dọc
    var size: Float,     // đường kính (dp)
) {
    fun toJson(): JSONObject = JSONObject()
        .put("id", id).put("label", label).put("action", action.toJson())
        .put("x", x.toDouble()).put("y", y.toDouble()).put("size", size.toDouble())

    companion object {
        fun fromJson(o: JSONObject): PadButton? {
            val a = PadAction.fromJson(o.optJSONObject("action") ?: return null) ?: return null
            return PadButton(
                id = o.optString("id", UUID.randomUUID().toString()),
                label = o.optString("label"), action = a,
                x = o.optDouble("x", 0.5).toFloat(), y = o.optDouble("y", 0.5).toFloat(),
                size = o.optDouble("size", 64.0).toFloat(),
            )
        }
    }
}

enum class GyroMode { OFF, ALWAYS, WHILE_AIMING }

/** Cách gửi input vào trang: tay cầm ảo / chuột+phím tổng hợp / cả hai */
enum class InputMode(val usesPad: Boolean, val usesKbm: Boolean, val title: String) {
    GAMEPAD(true, false, "Tay cầm ảo (khuyên dùng)"),
    KEYBOARD_MOUSE(false, true, "Chuột + Phím"),
    BOTH(true, true, "Cả hai (song song)"),
}

class PadSettings {
    var enabled = true
    var opacity = 0.6f
    var lookSensitivity = 1.0f
    var gyroMode = GyroMode.OFF
    var gyroSensitivity = 1.0f
    var gyroInvertX = false
    var gyroInvertY = false
    var inputMode = InputMode.GAMEPAD

    // Joystick đi (WASD)
    var joyX = 0.13f
    var joyY = 0.70f
    var joySize = 150f

    // Vùng vuốt xoay camera: tâm + kích thước theo tỉ lệ màn hình
    var lookX = 0.72f
    var lookY = 0.46f
    var lookWidth = 0.38f
    var lookHeight = 0.72f

    /** Chạm = chuột: khi game khóa chuột, vùng trống thành touchpad (kéo = di chuyển con trỏ, chạm = click trái) */
    var touchMouse = false

    var buttons: MutableList<PadButton> = defaultButtons()

    fun clampLookPad() {
        lookWidth = lookWidth.coerceIn(0.12f, 0.9f)
        lookHeight = lookHeight.coerceIn(0.15f, 0.95f)
        lookX = lookX.coerceIn(lookWidth / 2, 1 - lookWidth / 2)
        lookY = lookY.coerceIn(lookHeight / 2, 1 - lookHeight / 2)
    }

    fun resetLookPad() {
        val d = PadSettings()
        lookX = d.lookX; lookY = d.lookY; lookWidth = d.lookWidth; lookHeight = d.lookHeight
    }

    fun toJson(): JSONObject = JSONObject()
        .put("enabled", enabled).put("opacity", opacity.toDouble())
        .put("lookSens", lookSensitivity.toDouble())
        .put("gyroMode", gyroMode.name).put("gyroSens", gyroSensitivity.toDouble())
        .put("gyroInvX", gyroInvertX).put("gyroInvY", gyroInvertY)
        .put("inputMode", inputMode.name)
        .put("joyX", joyX.toDouble()).put("joyY", joyY.toDouble()).put("joySize", joySize.toDouble())
        .put("lookX", lookX.toDouble()).put("lookY", lookY.toDouble())
        .put("lookW", lookWidth.toDouble()).put("lookH", lookHeight.toDouble())
        .put("touchMouse", touchMouse)
        .put("buttons", JSONArray().also { arr -> buttons.forEach { arr.put(it.toJson()) } })

    companion object {
        fun defaultButtons(): MutableList<PadButton> = mutableListOf(
            PadButton(label = "Bắn", action = PadAction.Mouse(0), x = 0.88f, y = 0.58f, size = 92f),
            PadButton(label = "Ngắm", action = PadAction.Mouse(2), x = 0.76f, y = 0.70f, size = 72f),
            PadButton(label = "Nhảy", action = PadAction.Key(KeySpec.SPACE), x = 0.92f, y = 0.82f, size = 64f),
            PadButton(label = "R", action = PadAction.Key(KeySpec.parse("R")!!), x = 0.66f, y = 0.84f, size = 56f),
            PadButton(label = "Ngồi", action = PadAction.Key(KeySpec.CTRL), x = 0.40f, y = 0.84f, size = 56f),
            PadButton(label = "Chạy", action = PadAction.Key(KeySpec.SHIFT), x = 0.28f, y = 0.48f, size = 56f),
        )

        fun fromJson(o: JSONObject): PadSettings {
            val s = PadSettings()
            s.enabled = o.optBoolean("enabled", s.enabled)
            s.opacity = o.optDouble("opacity", s.opacity.toDouble()).toFloat()
            s.lookSensitivity = o.optDouble("lookSens", s.lookSensitivity.toDouble()).toFloat()
            s.gyroMode = runCatching { GyroMode.valueOf(o.optString("gyroMode")) }.getOrDefault(s.gyroMode)
            s.gyroSensitivity = o.optDouble("gyroSens", s.gyroSensitivity.toDouble()).toFloat()
            s.gyroInvertX = o.optBoolean("gyroInvX", s.gyroInvertX)
            s.gyroInvertY = o.optBoolean("gyroInvY", s.gyroInvertY)
            s.inputMode = runCatching { InputMode.valueOf(o.optString("inputMode")) }.getOrDefault(s.inputMode)
            s.joyX = o.optDouble("joyX", s.joyX.toDouble()).toFloat()
            s.joyY = o.optDouble("joyY", s.joyY.toDouble()).toFloat()
            s.joySize = o.optDouble("joySize", s.joySize.toDouble()).toFloat()
            s.lookX = o.optDouble("lookX", s.lookX.toDouble()).toFloat()
            s.lookY = o.optDouble("lookY", s.lookY.toDouble()).toFloat()
            s.lookWidth = o.optDouble("lookW", s.lookWidth.toDouble()).toFloat()
            s.lookHeight = o.optDouble("lookH", s.lookHeight.toDouble()).toFloat()
            s.touchMouse = o.optBoolean("touchMouse", s.touchMouse)
            o.optJSONArray("buttons")?.let { arr ->
                val list = mutableListOf<PadButton>()
                for (i in 0 until arr.length()) PadButton.fromJson(arr.getJSONObject(i))?.let { list.add(it) }
                s.buttons = list
            }
            s.clampLookPad()
            return s
        }
    }
}

object PadStore {
    private const val PREFS = "hknow.pad"
    private const val KEY = "settings.v1"
    private lateinit var appContext: Context
    var settings = PadSettings()

    fun init(context: Context) {
        appContext = context.applicationContext
        val raw = appContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null)
        if (raw != null) {
            settings = runCatching { PadSettings.fromJson(JSONObject(raw)) }.getOrDefault(PadSettings())
        }
    }

    fun save() {
        appContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString(KEY, settings.toJson().toString()).apply()
    }
}
