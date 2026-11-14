import UIKit
import WebKit
import CoreMotion

/// Cách gửi input (nút ảo, joystick, vuốt, gyro, chuột thật) vào trang GeForce NOW.
///  - gamepad:       giả lập tay cầm Xbox qua `navigator.getGamepads()` (GFN đọc polling, không kiểm tra isTrusted)
///  - keyboardMouse: bắn KeyboardEvent / MouseEvent tổng hợp (cách cũ)
///  - both:          gửi song song cả hai
enum InputMode: Int, CaseIterable {
    case gamepad = 0
    case keyboardMouse = 1
    case both = 2

    var usesPad: Bool { self != .keyboardMouse }
    var usesKBM: Bool { self != .gamepad }

    var title: String {
        switch self {
        case .gamepad: return "Tay cầm ảo (khuyên dùng)"
        case .keyboardMouse: return "Chuột + Phím"
        case .both: return "Cả hai (song song)"
        }
    }
}

/// App chỉ gồm 1 WebView toàn màn hình mở trang GeForce NOW, kèm:
///  1. Giả lập Safari trên Mac (không cảm ứng) để GFN luôn hiện giao diện desktop.
///  2. Tay cầm Xbox ảo (Gamepad API) + chuột/phím tổng hợp -> điều khiển nhân vật trong game.
///  3. Bộ điều khiển ảo tùy chỉnh (joystick đi, vuốt để nhìn, nút bắn/ngắm/phím...) + gyro.
final class WebViewController: UIViewController, WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler {

    // MARK: - Cấu hình (có thể chỉnh)

    private let startURL = URL(string: "https://play.geforcenow.com")!

    /// Số pixel chuột tương ứng 1 radian xoay khi dùng gyro (ở độ nhạy 1.0)
    private let gyroPixelsPerRadian: Double = 700

    // --- Chỉ dùng cho chế độ tay cầm: đổi vuốt/gyro/chuột (pixel) thành cần gạt phải ---

    /// Tốc độ (pixel/giây) tương ứng gạt cần phải hết cỡ. GIẢM nếu camera quay chậm, TĂNG nếu quay quá nhanh.
    private let stickFullSpeed: Double = 2000

    /// Bù vùng chết của game: chuyển động rất nhỏ vẫn gạt cần ít nhất ngần này (0...0.3).
    private let stickDeadzoneBoost: Double = 0.10

    /// Hằng số làm mượt (giây). Nhỏ = nhạy/giật hơn, lớn = mượt nhưng trễ hơn.
    private let stickSmoothing: Double = 0.03

    private let desktopUA =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    // MARK: - Trạng thái

    var webView: WKWebView!
    let overlay = ControllerOverlayView()
    let gearButton = UIButton(type: .system)

    private var displayLink: CADisplayLink?
    private var pendingDX: CGFloat = 0
    private var pendingDY: CGFloat = 0

    // Làm mượt cần gạt phải (chế độ tay cầm)
    private var lastFlushTime: CFTimeInterval = 0
    private var stickVX: Double = 0
    private var stickVY: Double = 0
    private var stickWasActive = false

    // Cần gạt trái (joystick đi) lần gửi gần nhất, để khỏi gửi trùng
    private var lastLeftX: CGFloat = 0
    private var lastLeftY: CGFloat = 0

    private let motion = CMMotionManager()
    private var lastMotionTimestamp: TimeInterval = 0

    // Con trỏ chuột kiểu Windows: vẽ đè lên con trỏ hệ thống (đã bị ẩn) khi chuột đang rê trong app.
    // Click / chuột phải / cuộn / hover vẫn là sự kiện chuột GỐC của iPadOS gửi thẳng vào trang web.
    private let cursorView = CursorView()
    private var cursorPos = CGPoint.zero
    private var pointerInside = false

    /// Chống "tự bấm chuột": thời điểm bắt đầu khóa chuột + các nút đã thật sự được nhấn trong lúc khóa

    /// Chế độ gửi input, lưu lại giữa các lần mở app. Mặc định: tay cầm ảo.
    var inputMode: InputMode = InputMode(
        rawValue: UserDefaults.standard.integer(forKey: "gfnweb.inputMode.v1")
    ) ?? .gamepad {
        didSet {
            guard oldValue != inputMode else { return }
            UserDefaults.standard.set(inputMode.rawValue, forKey: "gfnweb.inputMode.v1")
            resetStick()
            applyPadState()
        }
    }

    /// true khi trang web (game) đang xin khóa chuột
    private var isMouseCaptured = false {
        didSet {
            guard oldValue != isMouseCaptured else { return }
            pendingDX = 0; pendingDY = 0
            resetStick()
            overlay.reset(notify: false)
            setNeedsUpdateOfPrefersPointerLocked()
            updateCursorVisibility()
            applyPadState()
        }
    }

    /// Bộ điều khiển ảo đang bật và dùng tay cầm: nút/joystick/vuốt/gyro chạy NGAY, không cần đợi game khóa chuột
    private var padLive: Bool {
        PadStore.shared.settings.enabled && inputMode.usesPad && !padEditing && !overlay.hudHidden
    }

    /// Có được gửi input vào trang không: đã khóa chuột (game đang bắt chuột) HOẶC tay cầm ảo đang hoạt động
    private var inputLive: Bool { isMouseCaptured || padLive }

    /// Bàn phím ảo iOS: UITextField ẩn làm firstResponder, mọi ký tự gõ được chuyển vào trang
    let keyField = KeyCatcherField()

    /// Đang ở chế độ chỉnh sửa bố cục nút
    var padEditing = false {
        didSet {
            overlay.editing = padEditing
            applyPadState()
        }
    }

    // MARK: - Giao diện toàn màn hình + khóa con trỏ hệ thống

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    /// Chỉ khóa con trỏ hệ thống khi vào game (xoay camera). Ngoài game để chuột chạy tự nhiên.
    override var prefersPointerLocked: Bool { isMouseCaptured }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .all }

    // MARK: - Vòng đời

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsAirPlayForMediaPlayback = false
        config.defaultWebpagePreferences.preferredContentMode = .desktop
        config.preferences.isElementFullscreenEnabled = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        // forMainFrameOnly: false -> phần giả lập Safari/Mac chạy cả trong iframe.
        // Phần Pointer Lock + tay cầm ảo chỉ hoạt động ở khung chính (xem injectedJS).
        let script = WKUserScript(
            source: WebViewController.injectedJS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(script)
        config.userContentController.add(self, name: "gfnLock")

        webView = WKWebView(frame: .zero, configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.customUserAgent = desktopUA
        webView.uiDelegate = self
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        if #available(iOS 16.4, *) { webView.isInspectable = true }

        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        // Lớp điều khiển ảo (nằm trên WebView)
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.isHidden = true
        view.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: view.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        overlay.onLook = { [weak self] dx, dy in self?.addLook(dx, dy) }
        overlay.onAction = { [weak self] action, down in self?.perform(action, down: down) }
        overlay.onJoystick = { [weak self] x, y in self?.sendLeft(x, y) }
        overlay.onEditButton = { [weak self] id, source in self?.presentButtonEditor(id, from: source) }
        overlay.onEditJoystick = { [weak self] source in self?.presentJoystickEditor(from: source) }
        overlay.onLongPressEmpty = { [weak self] point in self?.presentAddButtonAt(point) }
        overlay.reload()
        setupKeyField()

        setupGearButton()
        view.addSubview(cursorView)     // luôn nằm trên cùng
        setupPointer()

        // Gửi chuyển động chuột/gyro/vuốt vào trang theo nhịp màn hình (tối đa 120Hz)
        let link = CADisplayLink(target: self, selector: #selector(flushMouse(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        displayLink = link

        NotificationCenter.default.addObserver(
            self, selector: #selector(appWillResign),
            name: UIApplication.willResignActiveNotification, object: nil
        )

        applyPadState()
        webView.load(URLRequest(url: startURL))
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        setNeedsUpdateOfHomeIndicatorAutoHidden()
    }

    @objc private func appWillResign() {
        webView.evaluateJavaScript("document.exitPointerLock && document.exitPointerLock()")
        isMouseCaptured = false
    }

    // MARK: - Trạng thái bộ điều khiển ảo

    func applyPadState() {
        guard isViewLoaded else { return }
        let s = PadStore.shared.settings
        // TẮT: overlay ẩn hẳn (hitTest trả nil) => mọi chạm/vuốt đi thẳng xuống WKWebView.
        // BẬT: hiện nút ngay; overlay nuốt toàn bộ cảm ứng: nút/joystick chỉ nhận trong hình tròn,
        //      phần còn lại chỉ để vuốt xoay camera (cần gạt phải), không bao giờ thành click chuột.
        let show = s.enabled
        if !show {
            overlay.reset(notify: true)     // nhả mọi nút/phím đang giữ, đưa cần gạt về 0
            sendLeft(0, 0)
            pendingDX = 0; pendingDY = 0
            resetStick()
        }
        overlay.isHidden = !show
        overlay.isUserInteractionEnabled = show
        overlay.alpha = padEditing ? 1 : s.opacity
        updateGyro()
        refreshMenu()
        pushInputConfig()
    }

    /// Báo cho JS biết đang dùng tay cầm ảo và/hoặc chuột-phím tổng hợp.
    private func pushInputConfig() {
        guard let wv = webView else { return }
        let m = inputMode
        wv.evaluateJavaScript(
            "window.__gfnMouse&&window.__gfnMouse.config({pad:\(m.usesPad),kbm:\(m.usesKBM)})"
        )
    }

    private func resetStick() {
        stickVX = 0; stickVY = 0
        stickWasActive = false
        lastLeftX = 0; lastLeftY = 0
    }

    private func addLook(_ dx: CGFloat, _ dy: CGFloat) {
        guard inputLive else { return }
        let k = PadStore.shared.settings.lookSensitivity
        pendingDX += dx * k
        pendingDY += dy * k
    }

    func perform(_ action: PadAction, down: Bool) {
        switch action {
        case .mouse(let button):
            sendButton(button, down)
        case .key(let spec):
            sendKey(spec, down)
        case .releaseLock:
            if down { webView.evaluateJavaScript("document.exitPointerLock&&document.exitPointerLock()") }
        case .pad(let index):
            sendPad(index, down)
        case .toggleKeyboard:
            if down { toggleKeyboard() }
        case .toggleHUD:
            // Hoãn sang vòng lặp kế: toggle làm overlay reset() trong lúc đang xử lý chạm
            if down {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.overlay.hudHidden.toggle()
                    self.sendLeft(0, 0)
                    self.pendingDX = 0; self.pendingDY = 0
                    self.resetStick()
                    self.applyPadState()
                }
            }
        }
    }

    // MARK: - Gyro

    func updateGyro() {
        let s = PadStore.shared.settings
        let wanted = s.enabled && s.gyroMode != .off && inputLive && !padEditing && motion.isDeviceMotionAvailable
        if wanted, !motion.isDeviceMotionActive {
            lastMotionTimestamp = 0
            motion.deviceMotionUpdateInterval = 1.0 / 120.0
            motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
                if let data { self?.handleMotion(data) }
            }
        } else if !wanted, motion.isDeviceMotionActive {
            motion.stopDeviceMotionUpdates()
        }
    }

    /// Gyro -> pendingDX/DY (pixel). Ở chế độ tay cầm, flushMouse sẽ đổi tiếp thành cần gạt phải (axes[2], axes[3]).
    private func handleMotion(_ m: CMDeviceMotion) {
        let s = PadStore.shared.settings
        var dt = lastMotionTimestamp == 0 ? 1.0 / 120.0 : m.timestamp - lastMotionTimestamp
        lastMotionTimestamp = m.timestamp
        dt = min(max(dt, 0), 0.05)

        if s.gyroMode == .whileAiming && !overlay.aimHeld { return }
        guard inputLive else { return }

        let rr = m.rotationRate
        let g = m.gravity

        // Quay ngang (yaw): thành phần của tốc độ quay theo phương trọng lực
        let yawRate = rr.x * g.x + rr.y * g.y + rr.z * g.z

        // Nghiêng lên/xuống (pitch): quay quanh trục ngang của màn hình, phụ thuộc hướng xoay máy
        let pitchRate: Double
        switch view.window?.windowScene?.interfaceOrientation ?? .landscapeRight {
        case .landscapeRight: pitchRate = -rr.y
        case .landscapeLeft: pitchRate = rr.y
        case .portraitUpsideDown: pitchRate = -rr.x
        default: pitchRate = rr.x
        }

        let k = gyroPixelsPerRadian * Double(s.gyroSensitivity) * dt
        pendingDX += CGFloat(yawRate * k * (s.gyroInvertX ? -1 : 1))
        pendingDY += CGFloat(pitchRate * k * (s.gyroInvertY ? -1 : 1))
    }

    // MARK: - Con trỏ chuột kiểu Windows (ngoài game)

    private func setupPointer() {
        // Theo dõi vị trí con trỏ chuột để vẽ mũi tên Windows
        let hover = UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:)))
        view.addGestureRecognizer(hover)

        // Ẩn con trỏ tròn mặc định của iPadOS (đặt trên cả view lẫn webView)
        view.addInteraction(UIPointerInteraction(delegate: self))
        webView.addInteraction(UIPointerInteraction(delegate: self))
    }

    @objc private func handleHover(_ g: UIHoverGestureRecognizer) {
        switch g.state {
        case .began, .changed:
            pointerInside = true
            cursorPos = g.location(in: view)
        default:
            pointerInside = false
        }
        updateCursorVisibility()
    }

    private func updateCursorVisibility() {
        let show = pointerInside && !isMouseCaptured
        cursorView.isHidden = !show
        if show { cursorView.place(at: cursorPos) }
    }

    // MARK: - Gửi input vào trang (theo nhịp màn hình)

    @objc private func flushMouse(_ link: CADisplayLink) {
        let t = link.timestamp
        let dt = min(max(lastFlushTime == 0 ? 1.0 / 120.0 : t - lastFlushTime, 1.0 / 240.0), 0.05)
        lastFlushTime = t

        guard inputLive else { return }
        let dx = pendingDX, dy = pendingDY
        pendingDX = 0; pendingDY = 0
        let mode = inputMode

        var calls: [String] = []
        // Kênh chuột tổng hợp: gửi độ dời thô (vuốt / gyro) theo từng khung hình
        if mode.usesKBM, dx != 0 || dy != 0 {
            calls.append(String(format: "m.move(%.2f,%.2f)", dx, dy))
        }
        // Kênh tay cầm: đổi độ dời thành cần gạt phải (đã làm mượt)
        if mode.usesPad, let call = stickCall(dx: dx, dy: dy, dt: dt) {
            calls.append(call)
        }
        guard !calls.isEmpty else { return }
        // Bọc trong hàm để KHÔNG tạo biến toàn cục nào trên trang GFN
        webView.evaluateJavaScript("(function(m){if(m){" + calls.joined(separator: ";") + "}})(window.__gfnMouse)")
    }

    /// Đổi độ dời (pixel/khung hình) thành cần gạt phải [-1, 1].
    /// Cần gạt là VẬN TỐC, còn vuốt/gyro/chuột là VỊ TRÍ, nên dùng trung bình trượt theo vận tốc:
    /// tổng góc quay vẫn tỉ lệ với quãng vuốt, và cần tự về 0 khi dừng vuốt.
    private func stickCall(dx: CGFloat, dy: CGFloat, dt: Double) -> String? {
        let a = 1 - exp(-dt / stickSmoothing)
        stickVX += (Double(dx) / dt - stickVX) * a
        stickVY += (Double(dy) / dt - stickVY) * a

        let nx = stickVX / stickFullSpeed
        let ny = stickVY / stickFullSpeed
        let mag = hypot(nx, ny)

        if mag < 0.004 {
            stickVX = 0; stickVY = 0
            guard stickWasActive else { return nil }
            stickWasActive = false
            return "m.stick(0,0)"
        }
        stickWasActive = true

        // Bù vùng chết theo hướng (giữ nguyên hướng gạt), giới hạn trong vòng tròn đơn vị
        let out = min(1, stickDeadzoneBoost + (1 - stickDeadzoneBoost) * mag)
        let k = out / mag
        return String(format: "m.stick(%.4f,%.4f)", nx * k, ny * k)
    }

    /// Joystick đi (analog) -> cần gạt trái (axes[0], axes[1]). x, y trong [-1, 1], y dương = xuống.
    private func sendLeft(_ x: CGFloat, _ y: CGFloat) {
        guard inputMode.usesPad else { return }
        var lx = x, ly = y
        if !inputLive { lx = 0; ly = 0 }
        let mag = hypot(lx, ly)
        if mag < 0.05 {
            lx = 0; ly = 0
        } else if mag > 1 {
            lx /= mag; ly /= mag
        }
        lx = (lx * 1000).rounded() / 1000
        ly = (ly * 1000).rounded() / 1000
        guard lx != lastLeftX || ly != lastLeftY else { return }
        lastLeftX = lx; lastLeftY = ly
        webView.evaluateJavaScript(
            String(format: "window.__gfnMouse&&window.__gfnMouse.left(%.3f,%.3f)", lx, ly)
        )
    }

    // Lệnh NHẢ luôn được gửi (không chặn bởi inputLive) để không bao giờ kẹt nút khi tắt / ẩn HUD
    private func sendButton(_ button: Int, _ pressed: Bool) {
        guard inputLive || !pressed else { return }
        webView.evaluateJavaScript(
            "window.__gfnMouse&&window.__gfnMouse.button(\(button),\(pressed ? "true" : "false"))"
        )
    }

    private func sendPad(_ index: Int, _ down: Bool) {
        guard inputLive || !down else { return }
        webView.evaluateJavaScript(
            "window.__gfnMouse&&window.__gfnMouse.pad(\(index),\(down ? "true" : "false"))"
        )
    }

    private func sendKey(_ spec: KeySpec, _ down: Bool) {
        guard inputLive || !down else { return }
        let js = "window.__gfnMouse&&window.__gfnMouse.key(\"\(spec.key)\",\"\(spec.code)\",\(spec.keyCode),\(down ? "true" : "false"))"
        webView.evaluateJavaScript(js)
    }

    // MARK: - Bàn phím ảo iOS -> trang web

    private func setupKeyField() {
        keyField.frame = CGRect(x: -100, y: -100, width: 10, height: 10)
        keyField.alpha = 0.01
        keyField.autocorrectionType = .no
        keyField.autocapitalizationType = .none
        keyField.spellCheckingType = .no
        keyField.smartQuotesType = .no
        keyField.smartDashesType = .no
        keyField.smartInsertDeleteType = .no
        keyField.returnKeyType = .send
        keyField.text = ""
        keyField.onText = { [weak self] text in self?.sendTyped(text) }
        keyField.onBackspace = { [weak self] in self?.callTyping("backspace()") }
        keyField.onReturn = { [weak self] in self?.callTyping("enter()") }
        view.addSubview(keyField)
    }

    func toggleKeyboard() {
        if keyField.isFirstResponder { keyField.resignFirstResponder() } else { keyField.becomeFirstResponder() }
    }

    private func sendTyped(_ text: String) {
        guard !text.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: [text], options: []),
              let arr = String(data: data, encoding: .utf8) else { return }
        callTyping("type(\(arr)[0])")
    }

    private func callTyping(_ call: String) {
        webView.evaluateJavaScript("window.__gfnMouse&&window.__gfnMouse.\(call)")
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "gfnLock", let locked = (message.body as? NSNumber)?.boolValue {
            isMouseCaptured = locked
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        isMouseCaptured = false
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Trang mới = ngữ cảnh JS mới: gửi lại cấu hình => tay cầm ảo được cắm ngay (không đợi Pointer Lock)
        pushInputConfig()
    }

    // MARK: - WKUIDelegate

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }

    @available(iOS 15.0, *)
    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        decisionHandler(.grant)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }

    // MARK: - JavaScript chèn vào trang

    private static let injectedJS = #"""
    (function () {
      'use strict';

      var isTop = (window.parent === window);

      // ===== 1. Giả làm Safari trên Mac: không có cảm ứng => GFN hiện giao diện desktop (mọi khung) =====
      try {
        Object.defineProperty(Navigator.prototype, 'maxTouchPoints', { get: function () { return 0; }, configurable: true });
        Object.defineProperty(Navigator.prototype, 'platform', { get: function () { return 'MacIntel'; }, configurable: true });
      } catch (e) {}
      try {
        ['ontouchstart', 'ontouchend', 'ontouchmove', 'ontouchcancel'].forEach(function (p) {
          [window, Window.prototype, Document.prototype, HTMLElement.prototype, Element.prototype].forEach(function (o) {
            try { delete o[p]; } catch (e) {}
          });
        });
        ['TouchEvent', 'Touch', 'TouchList'].forEach(function (n) {
          try { delete window[n]; } catch (e) {}
          try { if (n in window) window[n] = undefined; } catch (e) {}
        });
      } catch (e) {}
      try {
        var _mm = window.matchMedia.bind(window);
        window.matchMedia = function (q) {
          var s = String(q).replace(/\s+/g, '');
          if (/^\((any-)?(pointer:coarse|pointer:none|hover:none)\)$/.test(s)) return _mm('not all');
          if (/^\((any-)?(pointer:fine|hover:hover)\)$/.test(s)) return _mm('all');
          // Giả làm web app đã "Thêm vào Màn hình chính" (chế độ standalone)
          if (/^\(display-mode:(standalone|fullscreen)\)$/.test(s)) return _mm('all');
          if (/^\(display-mode:browser\)$/.test(s)) return _mm('not all');
          return _mm(String(q));
        };
      } catch (e) {}
      try {
        Object.defineProperty(Navigator.prototype, 'standalone', { get: function () { return true; }, configurable: true });
      } catch (e) {}

      // Khung con (iframe) chỉ cần phần giả lập ở trên. Trình phát GFN chạy ở khung chính
      // (bằng chứng: yêu cầu khóa chuột đã bị hook khi script chỉ chạy ở khung chính).
      if (!isTop) return;

      // ===== 2. Pointer Lock giả + chuột/phím tổng hợp do app gửi vào =====

      // Nơi nhận sự kiện chuột/phím tổng hợp: 'element' (phần tử đang khóa, sự kiện nổi bọt lên
      // document và window), 'document' hoặc 'window'. Thử đổi nếu cần.
      var KBM_TARGET = 'element';

      var lockEl = null;
      var buttonsMask = 0;
      var pressedButtons = {};
      var downKeys = {};
      var mods = { shift: false, ctrl: false, alt: false };

      // Cấu hình do Swift đẩy vào qua config(): dùng tay cầm ảo và/hoặc chuột-phím tổng hợp
      var mode = { pad: true, kbm: false };   // mặc định dùng tay cầm; Swift sẽ gửi lại qua config()

      function post(v) {
        try { window.webkit.messageHandlers.gfnLock.postMessage(!!v); } catch (e) {}
      }
      function fireLockChange() {
        setTimeout(function () { document.dispatchEvent(new Event('pointerlockchange')); }, 0);
      }
      function ensureFocus() {
        try { window.focus(); } catch (e) {}
      }

      try {
        Object.defineProperty(Document.prototype, 'pointerLockElement', {
          get: function () { return lockEl; }, configurable: true
        });
        Element.prototype.requestPointerLock = function () {
          lockEl = this; buttonsMask = 0;
          pressedButtons = {};
          ensureFocus();
          syncPad();                 // (tay cầm đã cắm từ lúc tải trang; gọi lại cho chắc)
          post(true); fireLockChange();
          return Promise.resolve();
        };
        Document.prototype.exitPointerLock = function () {
          if (!lockEl) return;
          releaseAll();
          lockEl = null; buttonsMask = 0;
          syncPad();                 // tay cầm vẫn cắm; chỉ rút khi đổi sang chế độ Chuột + Phím
          post(false); fireLockChange();
        };
      } catch (e) {}

      // Khi đang khóa: chặn sự kiện chuột "thật" để khỏi bị nhân đôi với sự kiện native
      ['mousemove', 'mousedown', 'mouseup', 'click', 'dblclick', 'auxclick', 'contextmenu',
       'pointermove', 'pointerdown', 'pointerup'].forEach(function (t) {
        window.addEventListener(t, function (e) {
          if (lockEl && e.isTrusted) { e.stopImmediatePropagation(); e.preventDefault(); }
        }, true);
      });

      // Nhấn Esc (bàn phím thật) để thả chuột, giống trình duyệt thật
      window.addEventListener('keydown', function (e) {
        if (lockEl && e.key === 'Escape' && e.isTrusted) document.exitPointerLock();
      }, true);

      function kbmTarget() {
        if (KBM_TARGET === 'window') return window;
        if (KBM_TARGET === 'document') return document;
        return lockEl || document.activeElement || document.body;
      }

      function fire(type, init) {
        var t = kbmTarget();
        if (!t) return;
        var r = (lockEl || document.documentElement).getBoundingClientRect();
        var cx = r.left + r.width / 2, cy = r.top + r.height / 2;
        var base = {
          bubbles: true, cancelable: true, composed: true, view: window,
          clientX: cx, clientY: cy, screenX: cx, screenY: cy,
          buttons: buttonsMask
        };
        for (var k in init) base[k] = init[k];
        var ev;
        if (type.indexOf('pointer') === 0 && window.PointerEvent) {
          base.pointerType = 'mouse'; base.pointerId = 1; base.isPrimary = true;
          ev = new PointerEvent(type, base);
        } else {
          ev = new MouseEvent(type, base);
        }
        if (init.movementX !== undefined) {
          try {
            Object.defineProperty(ev, 'movementX', { value: init.movementX });
            Object.defineProperty(ev, 'movementY', { value: init.movementY });
          } catch (e) {}
        }
        t.dispatchEvent(ev);
      }

      // Tính lại phím bổ trợ từ các phím đang giữ (hỗ trợ cả trái và phải)
      function setMod() {
        mods.shift = !!(downKeys.ShiftLeft || downKeys.ShiftRight);
        mods.ctrl = !!(downKeys.ControlLeft || downKeys.ControlRight);
        mods.alt = !!(downKeys.AltLeft || downKeys.AltRight);
      }

      function fireKey(type, key, code, keyCode) {
        var t = kbmTarget();
        if (!t) return;
        var ev = new KeyboardEvent(type, {
          key: key, code: code, bubbles: true, cancelable: true, composed: true, view: window,
          shiftKey: mods.shift, ctrlKey: mods.ctrl, altKey: mods.alt, repeat: false
        });
        try {
          Object.defineProperty(ev, 'keyCode', { value: keyCode });
          Object.defineProperty(ev, 'which', { value: keyCode });
        } catch (e) {}
        t.dispatchEvent(ev);
      }

      // Nhả các phím/nút chuột đang giữ trên kênh tổng hợp (không xóa trạng thái)
      function releaseKbmHeld() {
        if (!lockEl) return;
        Object.keys(downKeys).forEach(function (code) {
          var d = downKeys[code];
          fireKey('keyup', d[0], code, d[1]);
        });
        Object.keys(pressedButtons).forEach(function (b) {
          buttonsMask = 0;
          fire('pointerup', { button: Number(b) });
          fire('mouseup', { button: Number(b) });
        });
        buttonsMask = 0;
      }

      function releaseAll() {
        if (mode.kbm) releaseKbmHeld();
        Object.keys(downKeys).forEach(function (code) {
          delete downKeys[code];
        });
        setMod();
        padHeld = {};
        pressedButtons = {};
        buttonsMask = 0;
        leftAnalog.x = 0; leftAnalog.y = 0;
        rightStick.x = 0; rightStick.y = 0;
        recomputePad();
      }

      // ===== 3. Tay cầm Xbox ảo (Gamepad API): GFN đọc polling navigator.getGamepads() =====

      var PAD_ID = 'Xbox 360 Controller (STANDARD GAMEPAD Vendor: 045e Product: 028e)';
      var BTN_COUNT = 17;

      // Phím -> nút tay cầm (chỉ số theo mapping "standard"):
      // 0 A, 1 B, 2 X, 3 Y, 4 LB, 5 RB, 6 LT, 7 RT, 8 Back, 9 Start, 10 L3, 11 R3, 12-15 D-pad, 16 Guide
      // W/A/S/D không nằm ở đây: chúng điều khiển cần gạt trái (axes[0], axes[1]).
      var KEY_BTN = {
        Space: 0,
        ControlLeft: 1, ControlRight: 1, KeyC: 1,
        KeyR: 2, KeyE: 2, KeyF: 2,
        KeyQ: 3, KeyX: 3, Digit1: 3, Digit2: 3, Digit3: 3, Digit4: 3, Digit5: 3,
        AltLeft: 4, AltRight: 4, KeyZ: 4,
        KeyG: 5,
        Tab: 8,
        Escape: 9, Enter: 9,
        ShiftLeft: 10, ShiftRight: 10,
        KeyV: 11,
        ArrowUp: 12, ArrowDown: 13, ArrowLeft: 14, ArrowRight: 15
      };
      // Nút chuột (0 trái, 1 giữa, 2 phải, 3..) -> nút tay cầm
      var MOUSE_BTN = { 0: 7, 2: 6, 1: 11, 3: 4, 4: 5 };   // trái = RT (bắn), phải = LT (ngắm)

      var padOn = false;          // tay cầm ảo đang "cắm"
      var padHeld = {};           // nút tay cầm gán trực tiếp từ HUD (LB, RB, A, B, D-Pad...)
      var padIndex = 0;
      var padTs = 0;
      var padBtn = [];
      var padAx = [0, 0, 0, 0];
      var padSnap = null;
      var leftAnalog = { x: 0, y: 0 };            // joystick đi (analog)
      var rightStick = { x: 0, y: 0, t: 0 };      // vuốt / gyro / chuột
      var polls = 0;
      for (var bi = 0; bi < BTN_COUNT; bi++) padBtn.push(0);

      var rumble = {
        type: 'dual-rumble',
        playEffect: function () { return Promise.resolve('complete'); },
        reset: function () { return Promise.resolve('complete'); }
      };

      function now() { return (window.performance && performance.now) ? performance.now() : Date.now(); }
      function clamp1(v) { v = +v || 0; return v > 1 ? 1 : (v < -1 ? -1 : v); }

      // Tính lại toàn bộ nút + cần gạt từ trạng thái phím/chuột/joystick
      function recomputePad() {
        var b = [], i, k, code;
        for (i = 0; i < BTN_COUNT; i++) b.push(0);
        var dx = 0, dy = 0, keys = Object.keys(downKeys);
        for (k = 0; k < keys.length; k++) {
          code = keys[k];
          i = KEY_BTN[code];
          if (i !== undefined) b[i] = 1;
          if (code === 'KeyW') dy -= 1;
          else if (code === 'KeyS') dy += 1;
          else if (code === 'KeyA') dx -= 1;
          else if (code === 'KeyD') dx += 1;
        }
        var mb = Object.keys(pressedButtons);
        for (k = 0; k < mb.length; k++) {
          i = MOUSE_BTN[mb[k]];
          if (i !== undefined) b[i] = 1;
        }
        var ph = Object.keys(padHeld);
        for (k = 0; k < ph.length; k++) b[ph[k]] = 1;
        var lx, ly;
        if (leftAnalog.x !== 0 || leftAnalog.y !== 0) {      // analog thắng phím số
          lx = leftAnalog.x; ly = leftAnalog.y;
        } else {
          lx = dx; ly = dy;
          if (dx !== 0 && dy !== 0) { lx *= 0.7071; ly *= 0.7071; }
        }
        var a = [lx, ly, rightStick.x, rightStick.y];
        var changed = false;
        for (i = 0; i < BTN_COUNT; i++) { if (b[i] !== padBtn[i]) { changed = true; break; } }
        if (!changed) { for (i = 0; i < 4; i++) { if (a[i] !== padAx[i]) { changed = true; break; } } }
        if (changed) { padBtn = b; padAx = a; padTs = now(); padSnap = null; }
      }

      function buildSnap() {
        var buttons = [];
        for (var i = 0; i < BTN_COUNT; i++) {
          buttons.push({ pressed: padBtn[i] > 0.5, touched: padBtn[i] > 0, value: padBtn[i] });
        }
        return {
          id: PAD_ID, index: padIndex, connected: padOn, mapping: 'standard',
          timestamp: padTs, axes: padAx.slice(), buttons: buttons,
          vibrationActuator: rumble, hapticActuators: []
        };
      }

      // Danh sách 4 ô tay cầm: tay cầm thật (nếu có) + tay cầm ảo ở ô trống đầu tiên
      var realGetGamepads = Navigator.prototype.getGamepads;
      function buildList() {
        var list = [];
        try {
          var real = realGetGamepads ? realGetGamepads.call(navigator) : null;
          if (real) { for (var i = 0; i < real.length; i++) list.push(real[i] || null); }
        } catch (e) {}
        while (list.length < 4) list.push(null);
        if (padOn) {
          var slot = list.indexOf(null);
          if (slot >= 0) {
            if (slot !== padIndex) { padIndex = slot; padSnap = null; }
            if (!padSnap) padSnap = buildSnap();
            list[slot] = padSnap;
          }
        }
        return list;
      }
      function hookedGetGamepads() {
        polls++;
        // Chống kẹt cần: nếu app ngừng gửi cần phải quá 160ms thì tự về 0
        if (padOn && (rightStick.x !== 0 || rightStick.y !== 0) && now() - rightStick.t > 160) {
          rightStick.x = 0; rightStick.y = 0;
          recomputePad();
        }
        return buildList();
      }
      try {
        Object.defineProperty(Navigator.prototype, 'getGamepads', {
          value: hookedGetGamepads, writable: true, configurable: true, enumerable: true
        });
      } catch (e) {
        try { Navigator.prototype.getGamepads = hookedGetGamepads; } catch (e2) {}
      }

      function makeGamepadEvent(type, snap) {
        var ev = null;
        try {
          ev = new GamepadEvent(type, { gamepad: snap });
          if (ev.gamepad !== snap) ev = null;
        } catch (e) { ev = null; }
        if (!ev) {
          ev = new Event(type);
          try { Object.defineProperty(ev, 'gamepad', { value: snap }); } catch (e) {}
        }
        return ev;
      }
      var padAnnounced = false;      // đã phát gamepadconnected thật cho trang (để không phát bù trùng)
      function emitPadEvent(type, snap) {
        if (type === 'gamepaddisconnected') padAnnounced = false;
        setTimeout(function () {
          if (type === 'gamepadconnected') {
            if (!padOn) return;                       // đã rút trước khi kịp phát
            padAnnounced = true;
          }
          window.dispatchEvent(makeGamepadEvent(type, snap));
        }, 0);
      }

      // Nếu GFN đăng ký lắng nghe 'gamepadconnected' SAU khi tay cầm ảo đã cắm thì gọi bù một lần
      try {
        var addL = EventTarget.prototype.addEventListener;
        EventTarget.prototype.addEventListener = function (type, fn) {
          var r = addL.apply(this, arguments);
          if (type === 'gamepadconnected' && fn && padOn && padAnnounced && padSnap &&
              (this === window || this === undefined || this === null)) {
            setTimeout(function () {
              if (!padOn || !padSnap) return;
              var ev = makeGamepadEvent('gamepadconnected', padSnap);
              try {
                if (typeof fn === 'function') fn.call(window, ev);
                else if (fn.handleEvent) fn.handleEvent(ev);
              } catch (e) {}
            }, 0);
          }
          return r;
        };
      } catch (e) {}

      // Cắm / rút tay cầm ảo: cắm khi (dùng chế độ tay cầm) VÀ (đang khóa chuột)
      // Tay cầm ảo được cắm ngay khi trang tải xong (nếu chế độ có dùng tay cầm), không cần Pointer Lock
      var pageReady = (document.readyState !== 'loading');
      if (!pageReady) {
        document.addEventListener('DOMContentLoaded', function () { pageReady = true; syncPad(); }, { once: true });
        window.addEventListener('load', function () { pageReady = true; syncPad(); }, { once: true });
      }

      function syncPad() {
        var want = !!(mode.pad && pageReady);
        if (want === padOn) return;
        if (want) {
          padOn = true; padSnap = null; padTs = now();
          recomputePad();
          buildList();                                   // chọn ô + tạo snapshot
          if (padSnap) emitPadEvent('gamepadconnected', padSnap);
        } else {
          padOn = false;
          for (var i = 0; i < BTN_COUNT; i++) padBtn[i] = 0;
          padAx = [0, 0, 0, 0];
          leftAnalog.x = 0; leftAnalog.y = 0;
          rightStick.x = 0; rightStick.y = 0;
          padTs = now();
          padSnap = null;
          emitPadEvent('gamepaddisconnected', buildSnap());
        }
      }

      // ===== Gõ chữ từ bàn phím ảo iOS =====
      function isEditable(el) {
        return !!el && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.isContentEditable);
      }

      // Trả về true nếu trang đã chặn mặc định (preventDefault) ở keydown
      function typeKey(key, code, keyCode, withPress) {
        var t = document.activeElement || document.body;
        var res = false;
        ['keydown'].concat(withPress ? ['keypress'] : []).concat(['keyup']).forEach(function (type) {
          var ev = new KeyboardEvent(type, {
            key: key, code: code, bubbles: true, cancelable: true, composed: true, view: window
          });
          try {
            Object.defineProperty(ev, 'keyCode', { value: keyCode });
            Object.defineProperty(ev, 'which', { value: keyCode });
          } catch (e) {}
          t.dispatchEvent(ev);
          if (type === 'keydown' && ev.defaultPrevented) res = true;
        });
        return res;
      }

      function typeChar(ch) {
        var el = document.activeElement;
        if (isEditable(el)) {
          var ok = false;
          try { ok = document.execCommand('insertText', false, ch); } catch (e) {}
          if (ok) return;
        }
        var up = ch.toUpperCase();
        var code = /[a-z]/i.test(ch) ? 'Key' + up : (/[0-9]/.test(ch) ? 'Digit' + ch : (ch === ' ' ? 'Space' : ''));
        typeKey(ch, code, up.charCodeAt(0), true);
      }

      // Đếm số gói gửi qua RTCDataChannel (chỉ đếm để chẩn đoán, không đổi dữ liệu)
      var dcCount = {};
      try {
        var dcSend = RTCDataChannel.prototype.send;
        RTCDataChannel.prototype.send = function () {
          try { var l = this.label || '?'; dcCount[l] = (dcCount[l] || 0) + 1; } catch (e) {}
          return dcSend.apply(this, arguments);
        };
      } catch (e) {}

      // ===== 4. API cho app Swift gọi =====
      window.__gfnMouse = {
        // {pad: bool, kbm: bool}
        config: function (c) {
          var wasKbm = mode.kbm;
          mode.pad = !!(c && c.pad);
          mode.kbm = !!(c && c.kbm);
          if (wasKbm && !mode.kbm) releaseKbmHeld();
          syncPad();
        },
        // Độ dời thô (pixel) -> sự kiện chuột tổng hợp
        move: function (dx, dy) {
          if (!lockEl || !mode.kbm) return;
          fire('pointermove', { movementX: dx, movementY: dy });
          fire('mousemove', { movementX: dx, movementY: dy });
        },
        button: function (b, down) {
          if (!lockEl && !padOn) return;
          var bit = b === 0 ? 1 : b === 2 ? 2 : b === 1 ? 4 : (8 << (b - 3));
          if (down) { buttonsMask |= bit; pressedButtons[b] = true; }
          else { buttonsMask &= ~bit; delete pressedButtons[b]; }
          if (mode.kbm && lockEl) {
            ensureFocus();
            fire(down ? 'pointerdown' : 'pointerup', { button: b });
            fire(down ? 'mousedown' : 'mouseup', { button: b });
          }
          if (padOn) recomputePad();
        },
        key: function (key, code, keyCode, down) {
          if (!lockEl && !padOn) return;
          if (down) {
            if (downKeys[code]) return;
            downKeys[code] = [key, keyCode];
          } else {
            if (!downKeys[code]) return;
            delete downKeys[code];
          }
          setMod();
          if (mode.kbm && lockEl) {
            ensureFocus();
            fireKey(down ? 'keydown' : 'keyup', key, code, keyCode);
          }
          if (padOn) recomputePad();
        },
        // Nút tay cầm ảo gán trực tiếp (chỉ số theo mapping standard)
        pad: function (i, down) {
          if (!padOn) { if (down) return; }
          if (down) padHeld[i] = true; else delete padHeld[i];
          if (padOn) recomputePad();
        },
        // Gõ chữ từ bàn phím ảo iOS: ưu tiên chèn thẳng vào ô nhập liệu đang focus
        type: function (text) {
          for (var i = 0; i < text.length; i++) typeChar(text.charAt(i));
        },
        backspace: function () {
          var el = document.activeElement;
          if (isEditable(el)) {
            var ok = false;
            try { ok = document.execCommand('delete'); } catch (e) {}
            if (ok) return;
          }
          typeKey('Backspace', 'Backspace', 8);
        },
        enter: function () {
          var el = document.activeElement;
          var prevented = typeKey('Enter', 'Enter', 13, true);
          if (prevented || !isEditable(el)) return;
          if (el.tagName === 'TEXTAREA' || el.isContentEditable) {
            try { document.execCommand('insertLineBreak'); } catch (e) {}
          } else if (el.form && el.form.requestSubmit) {
            try { el.form.requestSubmit(); } catch (e) {}
          }
        },
        // Cần gạt phải (vuốt / gyro / chuột): x, y trong [-1, 1], y dương = nhìn xuống
        stick: function (x, y) {
          if (!padOn) return;
          rightStick.x = clamp1(x); rightStick.y = clamp1(y);
          rightStick.t = now();
          recomputePad();
        },
        // Cần gạt trái (joystick đi analog)
        left: function (x, y) {
          if (!padOn) return;
          leftAnalog.x = clamp1(x); leftAnalog.y = clamp1(y);
          recomputePad();
        },
        // Chẩn đoán: gọi từ Web Inspector -> __gfnMouse.stats()
        stats: function () {
          return {
            lock: !!lockEl, pad: mode.pad, kbm: mode.kbm, padOn: padOn, index: padIndex,
            polls: polls, axes: padAx.slice(), buttons: padBtn.join(''), dataChannelSends: dcCount
          };
        }
      };

      // Cắm tay cầm ảo ngay nếu trang đã sẵn sàng (nếu chưa: DOMContentLoaded / load / config() từ Swift sẽ cắm)
      syncPad();
    })();
    """#
}

// MARK: - Ẩn con trỏ tròn của iPadOS (app tự vẽ mũi tên Windows)

extension WebViewController: UIPointerInteractionDelegate {
    func pointerInteraction(_ interaction: UIPointerInteraction, regionFor request: UIPointerRegionRequest, defaultRegion: UIPointerRegion) -> UIPointerRegion? {
        defaultRegion
    }

    func pointerInteraction(_ interaction: UIPointerInteraction, styleFor region: UIPointerRegion) -> UIPointerStyle? {
        UIPointerStyle.hidden()
    }
}
