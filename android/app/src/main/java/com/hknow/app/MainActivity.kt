package com.hknow.app

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.app.AlertDialog
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Bundle
import android.text.InputType
import android.view.Gravity
import android.view.KeyEvent
import android.view.Surface
import android.view.View
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.webkit.CookieManager
import android.webkit.JavascriptInterface
import android.webkit.PermissionRequest
import android.webkit.WebChromeClient
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.TextView
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import org.json.JSONObject
import kotlin.math.exp
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min

/**
 * Bản Android của HKnow: một WebView toàn màn hình mở GeForce NOW + lớp điều khiển ảo.
 * Đoạn JS chèn vào trang (tay cầm Xbox ảo, giả lập desktop) dùng CHUNG với bản iOS (assets/inject.js,
 * sinh từ WebViewController.swift bằng tools/sync_js.py).
 */
class MainActivity : Activity(), SensorEventListener {

    // ----- Cấu hình -----
    private val startUrl = "https://play.geforcenow.com"
    private val desktopUA =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"
    private val gyroPixelsPerRadian = 700.0
    private val stickFullSpeed = 2000.0       // dp/giây ứng với gạt cần phải hết cỡ
    private val stickDeadzoneBoost = 0.10
    private val stickSmoothing = 0.03

    private lateinit var root: FrameLayout
    private lateinit var webView: WebView
    private lateinit var overlay: OverlayView
    private lateinit var gear: TextView
    private lateinit var keyField: EditText

    private val settings get() = PadStore.settings

    private var locked = false                 // trang đang xin khóa chuột (Pointer Lock)
    private var padEditing = false
        set(v) {
            field = v
            overlay.editing = v
            applyPadState()
        }

    private val padLive get() = settings.enabled && settings.inputMode.usesPad && !padEditing && !overlay.hudHidden
    private val inputLive get() = locked || padLive

    // Vuốt / gyro -> độ dời gộp theo từng khung hình
    private var pendingDX = 0f
    private var pendingDY = 0f
    private var stickVX = 0.0
    private var stickVY = 0.0
    private var stickWasActive = false
    private var pendingTX = 0f
    private var pendingTY = 0f
    private val touchMouseSpeed = 1.6f        // tốc độ con trỏ khi dùng touchpad
    private var lastLeftX = 0f
    private var lastLeftY = 0f
    private var lastFrameNanos = 0L

    private var pendingPermission: PermissionRequest? = null
    private var customView: View? = null
    private var customCallback: WebChromeClient.CustomViewCallback? = null

    private val frameCallback = object : android.view.Choreographer.FrameCallback {
        override fun doFrame(frameTimeNanos: Long) {
            flush(frameTimeNanos)
            android.view.Choreographer.getInstance().postFrameCallback(this)
        }
    }

    // ===================== Vòng đời =====================

    @SuppressLint("SetJavaScriptEnabled", "ClickableViewAccessibility")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        PadStore.init(this)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        hideSystemBars()

        root = FrameLayout(this).apply { setBackgroundColor(Color.BLACK) }
        setContentView(root)

        // ----- WebView -----
        webView = WebView(this)
        val ws = webView.settings
        ws.javaScriptEnabled = true
        ws.domStorageEnabled = true
        ws.databaseEnabled = true
        ws.mediaPlaybackRequiresUserGesture = false
        ws.userAgentString = desktopUA
        ws.useWideViewPort = true
        ws.loadWithOverviewMode = true
        ws.javaScriptCanOpenWindowsAutomatically = true
        ws.mixedContentMode = WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE
        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().setAcceptThirdPartyCookies(webView, true)
        WebView.setWebContentsDebuggingEnabled(true)
        webView.setBackgroundColor(Color.BLACK)
        webView.addJavascriptInterface(Bridge(), "HKBridge")
        webView.webViewClient = object : WebViewClient() {
            override fun onPageStarted(view: WebView, url: String?, favicon: android.graphics.Bitmap?) {
                locked = false
                if (!docStartSupported) view.evaluateJavascript(injectedScript, null)
            }

            override fun onPageFinished(view: WebView, url: String?) {
                pushInputConfig()
            }
        }
        webView.webChromeClient = object : WebChromeClient() {
            override fun onPermissionRequest(request: PermissionRequest) {
                runOnUiThread {
                    if (request.resources.contains(PermissionRequest.RESOURCE_AUDIO_CAPTURE) &&
                        checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED
                    ) {
                        pendingPermission = request
                        requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 7)
                    } else {
                        request.grant(request.resources)
                    }
                }
            }

            override fun onShowCustomView(view: View, callback: CustomViewCallback) {
                customView?.let { root.removeView(it) }
                customView = view
                customCallback = callback
                root.addView(view, 0, FrameLayout.LayoutParams(-1, -1))
                webView.visibility = View.INVISIBLE
            }

            override fun onHideCustomView() {
                customView?.let { root.removeView(it) }
                customView = null
                customCallback?.onCustomViewHidden()
                customCallback = null
                webView.visibility = View.VISIBLE
            }
        }
        root.addView(webView, FrameLayout.LayoutParams(-1, -1))
        installScript()

        // ----- Lớp điều khiển -----
        overlay = OverlayView(this)
        overlay.onLook = { dx, dy -> addLook(dx, dy) }
        overlay.onAction = { a, down -> perform(a, down) }
        overlay.onJoystick = { x, y -> sendLeft(x, y) }
        overlay.onEditButton = { id -> showButtonEditor(id) }
        overlay.onEditJoystick = { showJoystickEditor() }
        overlay.onEditLook = { showLookEditor() }
        overlay.onLongPressEmpty = { x, y -> showAddAt(x, y) }
        overlay.onPointerMove = { dx, dy -> pendingTX += dx * touchMouseSpeed; pendingTY += dy * touchMouseSpeed }
        overlay.onPointerClick = { touchClick() }
        root.addView(overlay, FrameLayout.LayoutParams(-1, -1))

        // ----- Nút menu góc trên trái -----
        val dp = resources.displayMetrics.density
        gear = TextView(this).apply {
            text = "🎮"
            textSize = 18f
            gravity = Gravity.CENTER
            alpha = 0.7f
            background = GradientDrawable().apply { setColor(0x66000000); cornerRadius = 18 * dp }
            setOnClickListener { showMenu() }
        }
        root.addView(gear, FrameLayout.LayoutParams((36 * dp).toInt(), (36 * dp).toInt()).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            topMargin = (10 * dp).toInt()
        })

        // ----- Ô nhập liệu ẩn cho bàn phím ảo -----
        keyField = EditText(this).apply {
            alpha = 0.01f
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS or
                InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD
            imeOptions = EditorInfo.IME_ACTION_SEND or EditorInfo.IME_FLAG_NO_EXTRACT_UI or EditorInfo.IME_FLAG_NO_FULLSCREEN
            setOnEditorActionListener { _, _, _ -> callTyping("enter()"); true }
            setOnKeyListener { _, code, ev ->
                if (ev.action == KeyEvent.ACTION_DOWN && code == KeyEvent.KEYCODE_DEL) { callTyping("backspace()"); true }
                else if (ev.action == KeyEvent.ACTION_DOWN && code == KeyEvent.KEYCODE_ENTER) { callTyping("enter()"); true }
                else false
            }
            addTextChangedListener(object : android.text.TextWatcher {
                override fun beforeTextChanged(s: CharSequence?, st: Int, c: Int, a: Int) {}
                override fun onTextChanged(s: CharSequence?, st: Int, b: Int, c: Int) {
                    if (s != null && s.isNotEmpty()) {
                        sendTyped(s.toString())
                        post { text?.clear() }      // ô luôn rỗng: không giữ chữ lại
                    }
                }
                override fun afterTextChanged(s: android.text.Editable?) {}
            })
        }
        root.addView(keyField, FrameLayout.LayoutParams((10 * dp).toInt(), (10 * dp).toInt()).apply {
            gravity = Gravity.BOTTOM or Gravity.START
        })

        applyPadState()
        android.view.Choreographer.getInstance().postFrameCallback(frameCallback)
        webView.loadUrl(startUrl)
    }

    private fun hideSystemBars() {
        window.decorView.systemUiVisibility = (View.SYSTEM_UI_FLAG_FULLSCREEN
            or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
            or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
            or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
            or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
            or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) hideSystemBars()
    }

    override fun onResume() {
        super.onResume()
        webView.onResume()
        updateGyro()
    }

    override fun onPause() {
        webView.evaluateJavascript("document.exitPointerLock&&document.exitPointerLock()", null)
        locked = false
        overlay.reset(true)
        stopGyro()
        webView.onPause()
        super.onPause()
    }

    override fun onDestroy() {
        android.view.Choreographer.getInstance().removeFrameCallback(frameCallback)
        super.onDestroy()
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        when {
            customView != null -> webView.webChromeClient?.onHideCustomView()
            webView.canGoBack() -> webView.goBack()
            else -> super.onBackPressed()
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        val req = pendingPermission ?: return
        pendingPermission = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) req.grant(req.resources) else req.deny()
    }

    // ===================== Script chèn vào trang =====================

    private var docStartSupported = false
    private val injectedScript: String by lazy {
        // Khung giả "webkit.messageHandlers" để đoạn JS dùng chung với iOS báo trạng thái Pointer Lock về app
        val shim = "window.webkit={messageHandlers:{gfnLock:{postMessage:function(v){try{HKBridge.gfnLock(!!v)}catch(e){}}}}};\n"
        shim + assets.open("inject.js").bufferedReader().use { it.readText() }
    }

    private fun installScript() {
        docStartSupported = WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)
        if (docStartSupported) {
            WebViewCompat.addDocumentStartJavaScript(webView, injectedScript, setOf("*"))
        }
    }

    inner class Bridge {
        @JavascriptInterface
        fun gfnLock(v: Boolean) {
            runOnUiThread {
                if (locked == v) return@runOnUiThread
                locked = v
                pendingDX = 0f; pendingDY = 0f
                resetStick()
                overlay.reset(false)
                applyPadState()
            }
        }
    }

    // ===================== Trạng thái bộ điều khiển =====================

    private fun applyPadState() {
        if (!::overlay.isInitialized) return
        val s = settings
        val show = s.enabled
        if (!show) {
            overlay.reset(true)
            sendLeft(0f, 0f)
            pendingDX = 0f; pendingDY = 0f
            resetStick()
        }
        overlay.visibility = if (show) View.VISIBLE else View.GONE
        overlay.touchpadActive = s.enabled && s.touchMouse && locked && !padEditing
        overlay.reload()
        updateGyro()
        pushInputConfig()
    }

    private fun pushInputConfig() {
        val m = settings.inputMode
        js("window.__gfnMouse&&window.__gfnMouse.config({pad:${m.usesPad},kbm:${m.usesKbm}})")
    }

    private fun resetStick() {
        stickVX = 0.0; stickVY = 0.0; stickWasActive = false
        lastLeftX = 0f; lastLeftY = 0f
    }

    private fun js(code: String) = webView.evaluateJavascript(code, null)

    private fun addLook(dx: Float, dy: Float) {
        if (!inputLive) return
        val k = settings.lookSensitivity
        pendingDX += dx * k
        pendingDY += dy * k
    }

    // ===================== Hành động =====================

    private fun perform(action: PadAction, down: Boolean) {
        when (action) {
            is PadAction.Mouse -> sendButton(action.button, down)
            is PadAction.Key -> sendKey(action.spec, down)
            PadAction.ReleaseLock -> if (down) js("document.exitPointerLock&&document.exitPointerLock()")
            is PadAction.Pad -> sendPad(action.index, down)
            PadAction.ToggleKeyboard -> if (down) toggleKeyboard()
            PadAction.ToggleHud -> if (down) root.post {
                overlay.hudHidden = !overlay.hudHidden
                sendLeft(0f, 0f)
                pendingDX = 0f; pendingDY = 0f
                resetStick()
                applyPadState()
            }
        }
    }

    // Lệnh NHẢ luôn được gửi (không chặn bởi inputLive) để không bao giờ kẹt nút khi tắt / ẩn HUD
    private fun sendButton(b: Int, pressed: Boolean) {
        if (!inputLive && pressed) return
        js("window.__gfnMouse&&window.__gfnMouse.button($b,$pressed)")
    }

    /** Chạm nhanh = click trái bằng chuột tổng hợp */
    private fun touchClick() {
        js("window.__gfnMouse&&window.__gfnMouse.tbutton(0,true)")
        root.postDelayed({ js("window.__gfnMouse&&window.__gfnMouse.tbutton(0,false)") }, 50)
    }

    private fun sendPad(i: Int, down: Boolean) {
        if (!inputLive && down) return
        js("window.__gfnMouse&&window.__gfnMouse.pad($i,$down)")
    }

    private fun sendKey(k: KeySpec, down: Boolean) {
        if (!inputLive && down) return
        js("window.__gfnMouse&&window.__gfnMouse.key(${JSONObject.quote(k.key)},${JSONObject.quote(k.code)},${k.keyCode},$down)")
    }

    private fun sendLeft(x: Float, y: Float) {
        if (!settings.inputMode.usesPad) return
        var lx = x; var ly = y
        if (!inputLive) { lx = 0f; ly = 0f }
        val mag = hypot(lx, ly)
        if (mag < 0.05f) { lx = 0f; ly = 0f } else if (mag > 1f) { lx /= mag; ly /= mag }
        lx = Math.round(lx * 1000f) / 1000f
        ly = Math.round(ly * 1000f) / 1000f
        if (lx == lastLeftX && ly == lastLeftY) return
        lastLeftX = lx; lastLeftY = ly
        js("window.__gfnMouse&&window.__gfnMouse.left(${"%.3f".format(java.util.Locale.US, lx)},${"%.3f".format(java.util.Locale.US, ly)})")
    }

    // ===================== Gửi vuốt / gyro theo từng khung hình =====================

    private fun flush(nanos: Long) {
        val dt = if (lastFrameNanos == 0L) 1.0 / 120.0 else (nanos - lastFrameNanos) / 1e9
        lastFrameNanos = nanos
        val step = min(max(dt, 1.0 / 240.0), 0.05)

        if (!inputLive) return
        val dx = pendingDX; val dy = pendingDY
        pendingDX = 0f; pendingDY = 0f
        val tx = pendingTX; val ty = pendingTY
        pendingTX = 0f; pendingTY = 0f
        val mode = settings.inputMode

        val calls = ArrayList<String>()
        if (tx != 0f || ty != 0f) {
            calls.add("m.tmove(${"%.2f".format(java.util.Locale.US, tx)},${"%.2f".format(java.util.Locale.US, ty)})")
        }
        if (mode.usesKbm && (dx != 0f || dy != 0f)) {
            calls.add("m.move(${"%.2f".format(java.util.Locale.US, dx)},${"%.2f".format(java.util.Locale.US, dy)})")
        }
        if (mode.usesPad) stickCall(dx, dy, step)?.let { calls.add(it) }
        if (calls.isEmpty()) return
        js("(function(m){if(m){" + calls.joinToString(";") + "}})(window.__gfnMouse)")
    }

    /** Đổi độ dời (dp/khung) thành cần gạt phải [-1, 1] (vận tốc làm mượt) */
    private fun stickCall(dx: Float, dy: Float, dt: Double): String? {
        val a = 1 - exp(-dt / stickSmoothing)
        stickVX += (dx / dt - stickVX) * a
        stickVY += (dy / dt - stickVY) * a
        val nx = stickVX / stickFullSpeed
        val ny = stickVY / stickFullSpeed
        val mag = hypot(nx, ny)
        if (mag < 0.004) {
            stickVX = 0.0; stickVY = 0.0
            if (!stickWasActive) return null
            stickWasActive = false
            return "m.stick(0,0)"
        }
        stickWasActive = true
        val out = min(1.0, stickDeadzoneBoost + (1 - stickDeadzoneBoost) * mag)
        val k = out / mag
        return "m.stick(${"%.4f".format(java.util.Locale.US, nx * k)},${"%.4f".format(java.util.Locale.US, ny * k)})"
    }

    // ===================== Gyro =====================

    private val sensors by lazy { getSystemService(Context.SENSOR_SERVICE) as SensorManager }
    private var gyroActive = false
    private var lastGyroNanos = 0L
    private val gravity = FloatArray(3)

    private fun updateGyro() {
        val s = settings
        val wanted = s.enabled && s.gyroMode != GyroMode.OFF && inputLive && !padEditing
        if (wanted && !gyroActive) {
            val gyro = sensors.getDefaultSensor(Sensor.TYPE_GYROSCOPE) ?: return
            val grav = sensors.getDefaultSensor(Sensor.TYPE_GRAVITY) ?: sensors.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
            lastGyroNanos = 0L
            sensors.registerListener(this, gyro, SensorManager.SENSOR_DELAY_FASTEST)
            if (grav != null) sensors.registerListener(this, grav, SensorManager.SENSOR_DELAY_GAME)
            gyroActive = true
        } else if (!wanted && gyroActive) {
            stopGyro()
        }
    }

    private fun stopGyro() {
        if (!gyroActive) return
        sensors.unregisterListener(this)
        gyroActive = false
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    override fun onSensorChanged(e: SensorEvent) {
        when (e.sensor.type) {
            Sensor.TYPE_GRAVITY -> { gravity[0] = e.values[0]; gravity[1] = e.values[1]; gravity[2] = e.values[2] }
            Sensor.TYPE_ACCELEROMETER -> {          // lọc thấp để lấy hướng trọng lực khi máy không có cảm biến trọng lực
                for (i in 0..2) gravity[i] = gravity[i] * 0.9f + e.values[i] * 0.1f
            }
            Sensor.TYPE_GYROSCOPE -> handleGyro(e)
        }
    }

    private fun handleGyro(e: SensorEvent) {
        val s = settings
        var dt = if (lastGyroNanos == 0L) 1.0 / 120.0 else (e.timestamp - lastGyroNanos) / 1e9
        lastGyroNanos = e.timestamp
        dt = min(max(dt, 0.0), 0.05)

        if (s.gyroMode == GyroMode.WHILE_AIMING && !overlay.aimHeld) return
        if (!inputLive) return

        val wx = e.values[0].toDouble(); val wy = e.values[1].toDouble(); val wz = e.values[2].toDouble()
        val gl = hypot(hypot(gravity[0].toDouble(), gravity[1].toDouble()), gravity[2].toDouble())
        if (gl < 1.0) return
        // Quay ngang (yaw): thành phần tốc độ quay theo phương trọng lực (Android: vector trọng lực hướng LÊN => đổi dấu)
        val yawRate = -(wx * gravity[0] + wy * gravity[1] + wz * gravity[2]) / gl

        // Nghiêng lên / xuống (pitch): phụ thuộc hướng xoay màn hình
        @Suppress("DEPRECATION")
        val rotation = windowManager.defaultDisplay.rotation
        val pitchRate = when (rotation) {
            Surface.ROTATION_90 -> -wy
            Surface.ROTATION_270 -> wy
            Surface.ROTATION_180 -> -wx
            else -> wx
        }

        val dpPerRad = gyroPixelsPerRadian * s.gyroSensitivity * dt
        pendingDX += (yawRate * dpPerRad * (if (s.gyroInvertX) -1 else 1)).toFloat()
        pendingDY += (pitchRate * dpPerRad * (if (s.gyroInvertY) -1 else 1)).toFloat()
    }

    // ===================== Bàn phím ảo =====================

    private fun toggleKeyboard() {
        val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
        if (keyField.hasFocus()) {
            imm.hideSoftInputFromWindow(keyField.windowToken, 0)
            keyField.clearFocus()
            hideSystemBars()
        } else {
            keyField.requestFocus()
            imm.showSoftInput(keyField, InputMethodManager.SHOW_FORCED)
        }
    }

    private fun sendTyped(text: String) = callTyping("type(${JSONObject.quote(text)})")

    private fun callTyping(call: String) = js("window.__gfnMouse&&window.__gfnMouse.$call")

    // ===================== Menu =====================

    private fun commit() {
        PadStore.save()
        overlay.reload()
        applyPadState()
    }

    private fun mark(on: Boolean) = if (on) "✓ " else ""

    private fun showMenu() {
        val s = settings
        val items = ArrayList<Pair<String, () -> Unit>>()
        items += mark(s.enabled) + "Bộ điều khiển ảo" to { s.enabled = !s.enabled; commit() }
        items += "Chế độ nhập liệu…" to {
            choose("Chế độ nhập liệu", InputMode.values().map { mark(s.inputMode == it) + it.title }) {
                s.inputMode = InputMode.values()[it]; resetStick(); commit()
            }
        }
        items += (if (padEditing) "Xong chỉnh sửa" else "Chỉnh sửa bố cục") to {
            padEditing = !padEditing
            if (!padEditing) PadStore.save()
        }
        items += "Thêm nút…" to { addButtonAt(0.5f, 0.5f) }
        items += (if (keyField.hasFocus()) "Tắt bàn phím ảo" else "Bật bàn phím ảo") to { toggleKeyboard() }
        items += (if (overlay.hudHidden) "Hiện HUD" else "Ẩn HUD (chạm tự do vào menu game)") to { perform(PadAction.ToggleHud, true) }
        items += "Gyro (nghiêng máy để ngắm)…" to {
            val modes = GyroMode.values()
            val names = listOf("Tắt", "Luôn bật", "Chỉ khi giữ nút Ngắm")
            choose("Gyro", modes.indices.map { mark(s.gyroMode == modes[it]) + names[it] }) { s.gyroMode = modes[it]; commit() }
        }
        items += "Độ nhạy gyro…" to { chooseValue("Độ nhạy gyro", listOf(0.5f, 1f, 1.5f, 2f, 3f, 4f), s.gyroSensitivity, { "${it}x" }) { s.gyroSensitivity = it; commit() } }
        items += mark(s.gyroInvertX) + "Đảo hướng ngang gyro" to { s.gyroInvertX = !s.gyroInvertX; commit() }
        items += mark(s.gyroInvertY) + "Đảo hướng dọc gyro" to { s.gyroInvertY = !s.gyroInvertY; commit() }
        items += "Độ nhạy vuốt màn hình…" to { chooseValue("Độ nhạy vuốt", listOf(0.5f, 0.75f, 1f, 1.5f, 2f, 3f), s.lookSensitivity, { "${it}x" }) { s.lookSensitivity = it; commit() } }
        items += "Độ đậm của nút…" to { chooseValue("Độ đậm", listOf(0.3f, 0.45f, 0.6f, 0.8f, 1f), s.opacity, { "${(it * 100).toInt()}%" }) { s.opacity = it; commit() } }
        items += mark(s.touchMouse) + "Chạm = chuột (khi game khóa chuột)" to { s.touchMouse = !s.touchMouse; commit() }
        items += "Thả chuột / chạm vào menu GFN" to { js("document.exitPointerLock&&document.exitPointerLock()") }
        items += "Tải lại trang" to { webView.reload() }
        items += "Đặt lại bố cục mặc định" to { PadStore.settings = PadSettings(); commit() }

        AlertDialog.Builder(this)
            .setItems(items.map { it.first }.toTypedArray()) { _, i -> items[i].second() }
            .show()
    }

    private fun choose(title: String, labels: List<String>, pick: (Int) -> Unit) {
        AlertDialog.Builder(this).setTitle(title)
            .setItems(labels.toTypedArray()) { _, i -> pick(i) }.show()
    }

    private fun chooseValue(title: String, values: List<Float>, current: Float, fmt: (Float) -> String, set: (Float) -> Unit) {
        choose(title, values.map { mark(kotlin.math.abs(it - current) < 0.01f) + fmt(it) }) { set(values[it]) }
    }

    // ----- Thêm nút -----

    private fun showAddAt(px: Float, py: Float) {
        if (!padEditing || overlay.width == 0 || overlay.height == 0) return
        val nx = (px / overlay.width).coerceIn(0.03f, 0.97f)
        val ny = (py / overlay.height).coerceIn(0.05f, 0.95f)
        val quick = listOf(PadAction.Mouse(0), PadAction.Mouse(2), PadAction.Key(KeySpec.SPACE), PadAction.ToggleKeyboard, PadAction.ToggleHud)
        val labels = listOf("Chọn hành động / phím…") + quick.map { it.title }
        choose("Thêm nút tại đây", labels) { i ->
            if (i == 0) addButtonAt(nx, ny) else insertButton(quick[i - 1], nx, ny)
        }
    }

    private fun addButtonAt(nx: Float, ny: Float) {
        showActionChooser("Chọn hành động cho nút mới") { insertButton(it, nx, ny) }
    }

    private fun insertButton(a: PadAction, nx: Float, ny: Float) {
        settings.buttons.add(PadButton(label = a.defaultLabel, action = a, x = nx, y = ny, size = 64f))
        PadStore.save()
        overlay.reload()
        padEditing = true
    }

    // ----- Bảng chọn hành động kiểu danh sách: hay dùng + "Tất cả phím & nút tay cầm" + "Phím khác" -----

    private fun showActionChooser(title: String, pick: (PadAction) -> Unit) {
        val presets = PadAction.presets
        val labels = presets.map { it.first } + listOf("Tất cả phím & nút tay cầm…", "Phím khác…")
        choose(title, labels) { i ->
            when {
                i < presets.size -> pick(presets[i].second)
                i == presets.size -> showGroupChooser(pick)
                else -> askCustomKey(pick)
            }
        }
    }

    private fun showGroupChooser(pick: (PadAction) -> Unit) {
        val groups = PadAction.catalog
        choose("Chọn nhóm", groups.map { it.first }) { gi ->
            val items = groups[gi].second
            choose(groups[gi].first, items.map { it.first }) { pick(items[it].second) }
        }
    }

    private fun askCustomKey(pick: (PadAction) -> Unit) {
        val input = EditText(this).apply { hint = "ví dụ: t, F5, space, ctrl"; inputType = InputType.TYPE_CLASS_TEXT }
        AlertDialog.Builder(this).setTitle("Phím khác").setView(input)
            .setNegativeButton("Hủy", null)
            .setPositiveButton("OK") { _, _ ->
                val spec = KeySpec.parse(input.text.toString())
                if (spec != null) pick(PadAction.Key(spec))
                else AlertDialog.Builder(this).setTitle("Không nhận ra phím này").setPositiveButton("OK", null).show()
            }.show()
    }

    // ----- Sửa nút / joystick / vùng xoay camera -----

    private fun mutate(id: String, change: (PadButton) -> Unit) {
        settings.buttons.firstOrNull { it.id == id }?.let(change)
        PadStore.save()
        overlay.reload()
    }

    private fun showButtonEditor(id: String) {
        val b = settings.buttons.firstOrNull { it.id == id } ?: return
        val items = listOf<Pair<String, () -> Unit>>(
            "Đổi hành động…" to { showActionChooser("Hành động mới") { a -> mutate(id) { it.action = a; it.label = a.defaultLabel } } },
            "Đổi tên nhãn…" to {
                val input = EditText(this).apply { setText(b.label) }
                AlertDialog.Builder(this).setTitle("Tên nhãn").setView(input)
                    .setNegativeButton("Hủy", null)
                    .setPositiveButton("OK") { _, _ -> mutate(id) { it.label = input.text.toString() } }.show()
            },
            "Nhân bản" to {
                settings.buttons.add(b.copy(id = java.util.UUID.randomUUID().toString(), x = min(b.x + 0.07f, 0.97f), y = min(b.y + 0.10f, 0.95f)))
                PadStore.save(); overlay.reload()
            },
            "Phóng to" to { mutate(id) { it.size = min(it.size * 1.2f, 220f) } },
            "Thu nhỏ" to { mutate(id) { it.size = max(it.size / 1.2f, 36f) } },
            "Xóa nút" to { settings.buttons.removeAll { it.id == id }; PadStore.save(); overlay.reload() },
        )
        AlertDialog.Builder(this).setTitle("${b.label} — ${b.action.title}")
            .setItems(items.map { it.first }.toTypedArray()) { _, i -> items[i].second() }
            .setNegativeButton("Xong", null).show()
    }

    private fun showJoystickEditor() {
        AlertDialog.Builder(this).setTitle("Joystick đi (W A S D)")
            .setItems(arrayOf("Phóng to", "Thu nhỏ")) { _, i ->
                settings.joySize = if (i == 0) min(settings.joySize * 1.2f, 300f) else max(settings.joySize / 1.2f, 90f)
                commit()
            }.setNegativeButton("Xong", null).show()
    }

    private fun showLookEditor() {
        val g = 1.15f
        val opts = listOf(
            Triple("Phóng to cả khung", g, g), Triple("Thu nhỏ cả khung", 1 / g, 1 / g),
            Triple("Rộng hơn (ngang)", g, 1f), Triple("Hẹp lại (ngang)", 1 / g, 1f),
            Triple("Cao hơn (dọc)", 1f, g), Triple("Thấp lại (dọc)", 1f, 1 / g),
        )
        AlertDialog.Builder(this).setTitle("Vùng xoay camera (kéo khung để di chuyển)")
            .setItems((opts.map { it.first } + "Đặt lại vị trí & kích thước").toTypedArray()) { _, i ->
                if (i < opts.size) {
                    settings.lookWidth *= opts[i].second
                    settings.lookHeight *= opts[i].third
                    settings.clampLookPad()
                } else settings.resetLookPad()
                commit()
            }.setNegativeButton("Xong", null).show()
    }
}
