import UIKit
import WebKit
import GameController
import CoreMotion

/// App chỉ gồm 1 WebView toàn màn hình mở trang GeForce NOW, kèm:
///  1. Giả lập Safari trên Mac (không cảm ứng) để GFN luôn hiện giao diện desktop.
///  2. Chuột native (GCMouse) -> xoay camera 360° trong game FPS.
///  3. Bộ điều khiển ảo tùy chỉnh (joystick đi, vuốt để nhìn, nút bắn/ngắm/phím...) + gyro.
final class WebViewController: UIViewController, WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler {

    // MARK: - Cấu hình (có thể chỉnh)

    private let startURL = URL(string: "https://play.geforcenow.com")!

    /// Độ nhạy chuột thật. Tăng nếu thấy camera xoay chậm, giảm nếu xoay quá nhanh.
    private let mouseSensitivity: CGFloat = 1.0

    /// Nếu nhìn lên/xuống của CHUỘT THẬT bị ngược thì đổi true <-> false.
    private let negateY = true

    /// Số pixel chuột tương ứng 1 radian xoay khi dùng gyro (ở độ nhạy 1.0)
    private let gyroPixelsPerRadian: Double = 700

    private let desktopUA =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    // MARK: - Trạng thái

    var webView: WKWebView!
    let overlay = ControllerOverlayView()
    let gearButton = UIButton(type: .system)

    private var displayLink: CADisplayLink?
    private var pendingDX: CGFloat = 0
    private var pendingDY: CGFloat = 0

    private let motion = CMMotionManager()
    private var lastMotionTimestamp: TimeInterval = 0

    /// true khi trang web (game) đang xin khóa chuột
    private var isMouseCaptured = false {
        didSet {
            guard oldValue != isMouseCaptured else { return }
            if !isMouseCaptured { pendingDX = 0; pendingDY = 0 }
            setNeedsUpdateOfPrefersPointerLocked()
            applyPadState()
        }
    }

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

        let script = WKUserScript(
            source: WebViewController.injectedJS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
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
        overlay.onEditButton = { [weak self] id, source in self?.presentButtonEditor(id, from: source) }
        overlay.onEditJoystick = { [weak self] source in self?.presentJoystickEditor(from: source) }
        overlay.reload()

        setupGearButton()
        setupMouse()

        // Gửi chuyển động chuột/gyro/vuốt vào trang theo nhịp màn hình (tối đa 120Hz)
        let link = CADisplayLink(target: self, selector: #selector(flushMouse))
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
        let show = s.enabled && (isMouseCaptured || padEditing)
        if !show { overlay.reset(notify: false) }
        overlay.isHidden = !show
        overlay.alpha = padEditing ? 1 : s.opacity
        updateGyro()
        refreshMenu()
    }

    private func addLook(_ dx: CGFloat, _ dy: CGFloat) {
        guard isMouseCaptured else { return }
        let k = PadStore.shared.settings.lookSensitivity
        pendingDX += dx * k
        pendingDY += dy * k
    }

    private func perform(_ action: PadAction, down: Bool) {
        switch action {
        case .mouse(let button):
            sendButton(button, down)
        case .key(let spec):
            sendKey(spec, down)
        case .releaseLock:
            if down { webView.evaluateJavaScript("document.exitPointerLock&&document.exitPointerLock()") }
        }
    }

    // MARK: - Gyro

    func updateGyro() {
        let s = PadStore.shared.settings
        let wanted = s.enabled && s.gyroMode != .off && isMouseCaptured && !padEditing && motion.isDeviceMotionAvailable
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

    private func handleMotion(_ m: CMDeviceMotion) {
        let s = PadStore.shared.settings
        var dt = lastMotionTimestamp == 0 ? 1.0 / 120.0 : m.timestamp - lastMotionTimestamp
        lastMotionTimestamp = m.timestamp
        dt = min(max(dt, 0), 0.05)

        if s.gyroMode == .whileAiming && !overlay.aimHeld { return }
        guard isMouseCaptured else { return }

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

    // MARK: - Chuột native (GameController)

    private func setupMouse() {
        NotificationCenter.default.addObserver(
            forName: .GCMouseDidConnect, object: nil, queue: .main
        ) { [weak self] note in
            if let mouse = note.object as? GCMouse { self?.bind(mouse) }
        }
        GCMouse.mice().forEach { bind($0) }
    }

    private func bind(_ mouse: GCMouse) {
        guard let input = mouse.mouseInput else { return }

        input.mouseMovedHandler = { [weak self] _, dx, dy in
            guard let self, self.isMouseCaptured else { return }
            self.pendingDX += CGFloat(dx) * self.mouseSensitivity
            // GCMouse: trục Y dương là hướng LÊN, còn web thì dương là xuống
            self.pendingDY += CGFloat(dy) * self.mouseSensitivity * (self.negateY ? -1 : 1)
        }
        input.leftButton.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.sendButton(0, pressed)
        }
        input.rightButton?.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.sendButton(2, pressed)
        }
        input.middleButton?.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.sendButton(1, pressed)
        }
        if let aux = input.auxiliaryButtons {
            for (i, button) in aux.enumerated() {
                button.pressedChangedHandler = { [weak self] _, _, pressed in
                    self?.sendButton(3 + i, pressed)
                }
            }
        }
    }

    @objc private func flushMouse() {
        guard isMouseCaptured, pendingDX != 0 || pendingDY != 0 else { return }
        let dx = pendingDX, dy = pendingDY
        pendingDX = 0; pendingDY = 0
        webView.evaluateJavaScript(
            String(format: "window.__gfnMouse&&window.__gfnMouse.move(%.2f,%.2f)", dx, dy)
        )
    }

    private func sendButton(_ button: Int, _ pressed: Bool) {
        guard isMouseCaptured else { return }
        webView.evaluateJavaScript(
            "window.__gfnMouse&&window.__gfnMouse.button(\(button),\(pressed ? "true" : "false"))"
        )
    }

    private func sendKey(_ spec: KeySpec, _ down: Bool) {
        guard isMouseCaptured else { return }
        let js = "window.__gfnMouse&&window.__gfnMouse.key(\"\(spec.key)\",\"\(spec.code)\",\(spec.keyCode),\(down ? "true" : "false"))"
        webView.evaluateJavaScript(js)
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

      // ===== 1. Giả làm Safari trên Mac: không có cảm ứng => GFN hiện giao diện desktop =====
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

      // ===== 2. Pointer Lock giả + chuột/phím do app gửi vào =====
      var lockEl = null;
      var buttonsMask = 0;
      var pressedButtons = {};
      var downKeys = {};
      var mods = { shift: false, ctrl: false, alt: false };

      function post(v) {
        try { window.webkit.messageHandlers.gfnLock.postMessage(!!v); } catch (e) {}
      }
      function fireLockChange() {
        setTimeout(function () { document.dispatchEvent(new Event('pointerlockchange')); }, 0);
      }

      try {
        Object.defineProperty(Document.prototype, 'pointerLockElement', {
          get: function () { return lockEl; }, configurable: true
        });
        Element.prototype.requestPointerLock = function () {
          lockEl = this; buttonsMask = 0;
          post(true); fireLockChange();
          return Promise.resolve();
        };
        Document.prototype.exitPointerLock = function () {
          if (!lockEl) return;
          releaseAll();
          lockEl = null; buttonsMask = 0;
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

      function fire(type, init) {
        var t = lockEl;
        if (!t) return;
        var r = t.getBoundingClientRect();
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

      function setMod(code, down) {
        if (code === 'ShiftLeft') mods.shift = down;
        else if (code === 'ControlLeft') mods.ctrl = down;
        else if (code === 'AltLeft') mods.alt = down;
      }

      function fireKey(type, key, code, keyCode) {
        var t = lockEl || document.activeElement || document.body;
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

      function releaseAll() {
        Object.keys(downKeys).forEach(function (code) {
          var d = downKeys[code];
          delete downKeys[code];
          setMod(code, false);
          fireKey('keyup', d[0], code, d[1]);
        });
        Object.keys(pressedButtons).forEach(function (b) {
          delete pressedButtons[b];
          buttonsMask = 0;
          fire('pointerup', { button: Number(b) });
          fire('mouseup', { button: Number(b) });
        });
        buttonsMask = 0;
      }

      window.__gfnMouse = {
        move: function (dx, dy) {
          if (!lockEl) return;
          fire('pointermove', { movementX: dx, movementY: dy });
          fire('mousemove', { movementX: dx, movementY: dy });
        },
        button: function (b, down) {
          if (!lockEl) return;
          var bit = b === 0 ? 1 : b === 2 ? 2 : b === 1 ? 4 : (8 << (b - 3));
          if (down) { buttonsMask |= bit; pressedButtons[b] = true; }
          else { buttonsMask &= ~bit; delete pressedButtons[b]; }
          fire(down ? 'pointerdown' : 'pointerup', { button: b });
          fire(down ? 'mousedown' : 'mouseup', { button: b });
        },
        key: function (key, code, keyCode, down) {
          if (!lockEl) return;
          if (down) {
            if (downKeys[code]) return;
            downKeys[code] = [key, keyCode];
          } else {
            if (!downKeys[code]) return;
            delete downKeys[code];
          }
          setMod(code, down);
          fireKey(down ? 'keydown' : 'keyup', key, code, keyCode);
        }
      };
    })();
    """#
}
