(function () {
  'use strict';

  var isTop = (window.parent === window);

  // ===== 1. Giả làm laptop Windows (Chrome/Edge). Cảm ứng: chỉ khi người dùng bật (window.__hkTouch) =====
  var TOUCH = (window.__hkTouch === true);
  try {
    Object.defineProperty(Navigator.prototype, 'maxTouchPoints', { get: function () { return TOUCH ? 5 : 0; }, configurable: true });
    Object.defineProperty(Navigator.prototype, 'platform', { get: function () { return 'Win32'; }, configurable: true });
  } catch (e) {}
  if (!TOUCH) {
    // Không cảm ứng => GFN hiện giao diện desktop và nhận chuột / phím / tay cầm như máy tính thường
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
  }
  try {
    var _mm = window.matchMedia.bind(window);
    window.matchMedia = function (q) {
      var s = String(q).replace(/\s+/g, '');
      if (TOUCH) {
        // Laptop cảm ứng: con trỏ chính là chuột/trackpad (fine), có thêm cảm ứng (any-pointer: coarse)
        if (/^\(pointer:fine\)$/.test(s)) return _mm('all');
        if (/^\(pointer:(coarse|none)\)$/.test(s)) return _mm('not all');
        if (/^\(any-pointer:(fine|coarse)\)$/.test(s)) return _mm('all');
        if (/^\(any-pointer:none\)$/.test(s)) return _mm('not all');
        if (/^\((any-)?hover:hover\)$/.test(s)) return _mm('all');
        if (/^\((any-)?hover:none\)$/.test(s)) return _mm('not all');
      } else {
        if (/^\((any-)?(pointer:coarse|pointer:none|hover:none)\)$/.test(s)) return _mm('not all');
        if (/^\((any-)?(pointer:fine|hover:hover)\)$/.test(s)) return _mm('all');
      }
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
  var mode = { pad: true, kbm: false, launcher: false, trigOnly: false, clicks: true, keyAlias: true };   // mặc định dùng tay cầm; Swift sẽ gửi lại qua config()

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
      if (mode.launcher) {       // chế độ Launcher: từ chối khóa chuột => GFN dùng toạ độ tuyệt đối, chạm đâu bấm đó
        setTimeout(function () { document.dispatchEvent(new Event('pointerlockerror')); }, 0);
        var err = window.DOMException ? new DOMException('Pointer lock is disabled in launcher mode', 'NotAllowedError')
                                    : new Error('Pointer lock is disabled in launcher mode');
        return Promise.reject(err);
      }
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
      // Chế độ Launcher: KHÔNG chặn, để cú chạm thật (isTrusted) tới tay GFN
      if (lockEl && !mode.launcher && e.isTrusted) { e.stopImmediatePropagation(); e.preventDefault(); }
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
    if (type.indexOf('pointer') === 0) base.pressure = buttonsMask ? 0.5 : 0;
    else if (type === 'mousedown' || type === 'mouseup') base.detail = 1;
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
    // Chuột + Phím: tay cầm ảo chỉ mang RT / LT (từ chuột trái / phải), mọi thứ khác để phím chuột lo
    if (mode.trigOnly) {
      for (i = 0; i < BTN_COUNT; i++) { if (i !== 6 && i !== 7) b[i] = 0; }
      lx = 0; ly = 0;
    }
    var a = [lx, ly, mode.trigOnly ? 0 : rightStick.x, mode.trigOnly ? 0 : rightStick.y];
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
  function typeKey(key, code, keyCode, withPress, shift) {
    var t = document.activeElement || document.body;
    var res = false;
    function mk(type, k, c, kc, sh) {
      var ev = new KeyboardEvent(type, {
        key: k, code: c, shiftKey: !!sh, bubbles: true, cancelable: true, composed: true, view: window
      });
      try {
        Object.defineProperty(ev, 'keyCode', { value: kc });
        Object.defineProperty(ev, 'which', { value: kc });
      } catch (e) {}
      t.dispatchEvent(ev);
      return ev;
    }
    if (shift) mk('keydown', 'Shift', 'ShiftLeft', 16, true);
    ['keydown'].concat(withPress ? ['keypress'] : []).concat(['keyup']).forEach(function (type) {
      var ev = mk(type, key, code, keyCode, shift);
      if (type === 'keydown' && ev.defaultPrevented) res = true;
    });
    if (shift) mk('keyup', 'Shift', 'ShiftLeft', 16, false);
    return res;
  }

  // Bàn phím Mỹ: ký tự -> [code, keyCode, cần Shift]. Cần cho "@", ".", "_", "-", ... trong mail / mật khẩu
  var SYM = {
    '-': ['Minus', 189, 0], '=': ['Equal', 187, 0], '[': ['BracketLeft', 219, 0], ']': ['BracketRight', 221, 0],
    '\\': ['Backslash', 220, 0], ';': ['Semicolon', 186, 0], "'": ['Quote', 222, 0], ',': ['Comma', 188, 0],
    '.': ['Period', 190, 0], '/': ['Slash', 191, 0], '`': ['Backquote', 192, 0],
    '_': ['Minus', 189, 1], '+': ['Equal', 187, 1], '{': ['BracketLeft', 219, 1], '}': ['BracketRight', 221, 1],
    '|': ['Backslash', 220, 1], ':': ['Semicolon', 186, 1], '"': ['Quote', 222, 1], '<': ['Comma', 188, 1],
    '>': ['Period', 190, 1], '?': ['Slash', 191, 1], '~': ['Backquote', 192, 1],
    '!': ['Digit1', 49, 1], '@': ['Digit2', 50, 1], '#': ['Digit3', 51, 1], '$': ['Digit4', 52, 1],
    '%': ['Digit5', 53, 1], '^': ['Digit6', 54, 1], '&': ['Digit7', 55, 1], '*': ['Digit8', 56, 1],
    '(': ['Digit9', 57, 1], ')': ['Digit0', 48, 1]
  };

  function typeChar(ch) {
    var el = document.activeElement;
    if (isEditable(el)) {
      var ok = false;
      try { ok = document.execCommand('insertText', false, ch); } catch (e) {}
      if (ok) return;
    }
    var up = ch.toUpperCase();
    if (/[a-z]/i.test(ch)) { typeKey(ch, 'Key' + up, up.charCodeAt(0), true, ch !== ch.toLowerCase()); return; }
    if (/[0-9]/.test(ch)) { typeKey(ch, 'Digit' + ch, ch.charCodeAt(0), true, false); return; }
    if (ch === ' ') { typeKey(' ', 'Space', 32, true, false); return; }
    var sy = SYM[ch];
    if (sy) { typeKey(ch, sy[0], sy[1], true, !!sy[2]); return; }
    typeKey(ch, '', up.charCodeAt(0), true, false);
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

  // ===== Con trỏ ảo / Trackpad (chế độ Chuột / Launcher): chạm màn hình -> sự kiện chuột tổng hợp =====
  // Swift gửi vị trí con trỏ chuẩn hóa 0...1 (theo WebView) và độ dời của con trỏ (cũng chuẩn hóa).
  //  - Trang CHƯA khóa chuột: sự kiện bắn tại đúng (clientX, clientY) lên phần tử nằm dưới con trỏ, như chuột thật.
  //  - Trang ĐANG khóa chuột (GFN dùng chế độ tương đối): sự kiện bắn lên phần tử đang khóa, mang movementX / movementY.
  //    Lúc này vị trí con trỏ trên máy chủ không đọc được từ toạ độ, nên chỉ có độ dời mới có nghĩa.
  // Bấm chuột luôn có nhịp: rê tới -> (30ms) nhấn -> (70ms) nhả -> click, để máy chủ GFN kịp nhận từng bước
  // (nhấn và nhả trong cùng một khung hình thường bị bỏ qua).
  var ptr = { x: 0, y: 0, buttons: 0, over: null, sent: 0, last: '' };

  // Khung nhìn của trang: dùng visualViewport (tính cả zoom / cuộn) nếu có, không thì innerWidth / innerHeight
  function ptrView() {
    var v = window.visualViewport;
    if (v && v.width > 0 && v.height > 0) {
      return { x0: v.offsetLeft || 0, y0: v.offsetTop || 0, w: v.width, h: v.height };
    }
    return { x0: 0, y0: 0, w: window.innerWidth || 1, h: window.innerHeight || 1 };
  }

  function ptrSet(nx, ny) {
    var v = ptrView();
    ptr.x = v.x0 + (+nx || 0) * v.w;
    ptr.y = v.y0 + (+ny || 0) * v.h;
  }

  // Phần tử nhận sự kiện: đang khóa chuột -> phần tử khóa; không thì phần tử dưới con trỏ (giống chuột thật)
  function ptrTarget() {
    if (lockEl && lockEl.isConnected !== false) return lockEl;
    var el = null;
    try { el = document.elementFromPoint(ptr.x, ptr.y); } catch (e) {}
    return el || document.body || document.documentElement;
  }

  function ptrEv(type, el, init) {
    if (!el) return;
    var base = {
      bubbles: true, cancelable: true, composed: true, view: window,
      clientX: ptr.x, clientY: ptr.y, screenX: ptr.x, screenY: ptr.y,
      buttons: ptr.buttons, button: 0
    };
    for (var k in init) base[k] = init[k];
    var ev;
    try {
      if (type.indexOf('pointer') === 0 && window.PointerEvent) {
        base.pointerType = 'mouse'; base.pointerId = 1; base.isPrimary = true;
        base.width = 1; base.height = 1;
        base.pressure = ptr.buttons ? 0.5 : 0;
        ev = new PointerEvent(type, base);
      } else if (type === 'wheel' && window.WheelEvent) {
        ev = new WheelEvent('wheel', base);
      } else {
        ev = new MouseEvent(type, base);
      }
    } catch (e) { return; }
    if (init.movementX !== undefined) {
      try {
        Object.defineProperty(ev, 'movementX', { value: init.movementX });
        Object.defineProperty(ev, 'movementY', { value: init.movementY });
      } catch (e) {}
    }
    try { el.dispatchEvent(ev); ptr.sent++; ptr.last = type; } catch (e) {}
  }

  function ptrBit(b) { return b === 0 ? 1 : (b === 2 ? 2 : 4); }

  // Rê chuột: pointermove (button -1 theo chuẩn) + mousemove
  function ptrMoveEv(el, dx, dy) {
    ptrEv('pointermove', el, { button: -1, movementX: dx, movementY: dy });
    ptrEv('mousemove', el, { movementX: dx, movementY: dy });
  }

  // Con trỏ đi vào phần tử mới (chỉ khi chưa khóa chuột): out / over để hiệu ứng hover của trang chạy
  function ptrEnter(el) {
    if (ptr.over === el) return;
    var old = ptr.over;
    ptr.over = el;
    if (old) {
      ptrEv('pointerout', old, { relatedTarget: el, button: -1 });
      ptrEv('mouseout', old, { relatedTarget: el });
    }
    ptrEv('pointerover', el, { relatedTarget: old || null, button: -1 });
    ptrEv('mouseover', el, { relatedTarget: old || null });
  }

  function ptrFocus(el) {
    try { if (el && el.focus) el.focus({ preventScroll: true }); } catch (e) {}
  }

  // ===== 4. API cho app Swift gọi =====
  window.__gfnMouse = {
    // {pad: bool, kbm: bool}
    config: function (c) {
      var wasKbm = mode.kbm;
      mode.pad = !!(c && c.pad);
      mode.kbm = !!(c && c.kbm);
      var wasLauncher = mode.launcher;
      mode.launcher = !!(c && c.launcher);
      mode.trigOnly = !!(c && c.trigOnly);
      mode.clicks = !(c && c.clicks === false);
      mode.keyAlias = !(c && c.keyAlias === false);
      if (wasKbm && !mode.kbm) releaseKbmHeld();
      syncPad();                                   // tay cầm ảo vẫn cắm ở chế độ Launcher
      // Vào chế độ Launcher: thả khóa chuột đang giữ để GFN chuyển sang toạ độ tuyệt đối
      if (mode.launcher && !wasLauncher && lockEl) document.exitPointerLock();
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
      if (mode.kbm && lockEl && mode.clicks) {
        ensureFocus();
        fire(down ? 'pointerdown' : 'pointerup', { button: b });
        fire(down ? 'mousedown' : 'mouseup', { button: b });
      }
      // Chuột + Phím: gửi KÈM phím tương ứng (LMB -> P, RMB -> 0, MMB -> I), giữ liên tục tới lúc nhả,
      // để gán phím phụ trong game (game không nhận click giả nhưng nhận phím). Vuốt ghìm tâm không làm nhả phím.
      if (mode.kbm && lockEl && mode.keyAlias) {
        var ka = b === 0 ? ['p', 'KeyP', 80] : (b === 2 ? ['0', 'Digit0', 48] : (b === 1 ? ['i', 'KeyI', 73] : null));
        if (ka) window.__gfnMouse.key(ka[0], ka[1], ka[2], down);
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
    // Chế độ Chuột + Phím chơi bằng cảm ứng: chưa ai bấm vào video nên game chưa xin khóa chuột.
    // Tự khóa vào khung video đang phát (khung hình lớn nhất) để chuột / phím tổng hợp có chỗ nhận.
    engage: function () {
      if (lockEl || !mode.kbm || mode.launcher) return false;
      var best = null, area = 0, vw = window.innerWidth * window.innerHeight;
      var vs = document.getElementsByTagName('video');
      for (var i = 0; i < vs.length; i++) {
        var v = vs[i], r = v.getBoundingClientRect(), a = r.width * r.height;
        if (v.videoWidth > 0 && !v.paused && a > area) { best = v; area = a; }
      }
      if (!best || area < vw * 0.4) return false;
      try { best.requestPointerLock(); } catch (e) { return false; }
      return true;
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
    // ----- Con trỏ ảo / Trackpad (chế độ Chuột / Launcher) -----
    // nx, ny: vị trí con trỏ (0...1); ndx, ndy: độ dời của con trỏ lần này (chuẩn hóa, 0 khi vừa chạm xuống)
    ptrMove: function (nx, ny, ndx, ndy) {
      ptrSet(nx, ny);
      var v = ptrView();
      var el = ptrTarget();
      if (!lockEl) ptrEnter(el);
      ptrMoveEv(el, (+ndx || 0) * v.w, (+ndy || 0) * v.h);
    },
    ptrDown: function (nx, ny, b) {
      ptrSet(nx, ny);
      var el = ptrTarget();
      if (!lockEl) ptrEnter(el);
      ptrFocus(el); ensureFocus();
      ptr.buttons |= ptrBit(b);
      ptrEv('pointerdown', el, { button: b, detail: 1 });
      ptrEv('mousedown', el, { button: b, detail: 1 });
    },
    ptrUp: function (nx, ny, b) {
      ptrSet(nx, ny);
      var el = ptrTarget();
      ptr.buttons &= ~ptrBit(b);
      ptrEv('pointerup', el, { button: b });
      ptrEv('mouseup', el, { button: b });
    },
    // Tap: rê tới -> nhấn -> giữ 70ms -> nhả -> click (n = 2: nhấp đúp)
    ptrClick: function (nx, ny, b, n) {
      ptrSet(nx, ny);
      var cx = ptr.x, cy = ptr.y, d = n || 1, bit = ptrBit(b);
      var el = ptrTarget();
      if (!lockEl) ptrEnter(el);
      ptrFocus(el); ensureFocus();
      ptrMoveEv(el, 0, 0);                         // chốt vị trí con trỏ trước khi bấm
      setTimeout(function () {
        ptr.x = cx; ptr.y = cy;
        ptr.buttons |= bit;
        ptrEv('pointerdown', el, { button: b, detail: d });
        ptrEv('mousedown', el, { button: b, detail: d });
        setTimeout(function () {
          ptr.x = cx; ptr.y = cy;
          ptr.buttons &= ~bit;
          ptrEv('pointerup', el, { button: b });
          ptrEv('mouseup', el, { button: b, detail: d });
          if (b === 0) {
            ptrEv('click', el, { button: 0, detail: d });
            if (d === 2) ptrEv('dblclick', el, { button: 0, detail: 2 });
          } else if (b === 2) {
            ptrEv('contextmenu', el, { button: 2 });
          }
        }, 70);
      }, 30);
    },
    ptrWheel: function (nx, ny, dy) {
      ptrSet(nx, ny);
      ptrEv('wheel', ptrTarget(), { deltaX: 0, deltaY: +dy || 0, deltaMode: 0 });
    },
    // Rời chế độ Chuột: nhả nút đang giữ, xóa trạng thái hover
    ptrReset: function () {
      var held = ptr.buttons;
      var el = ptr.over || document.body;
      if (held && el) {
        [0, 2, 1].forEach(function (b) {
          if (held & ptrBit(b)) {
            ptr.buttons &= ~ptrBit(b);
            ptrEv('pointerup', el, { button: b });
            ptrEv('mouseup', el, { button: b });
          }
        });
      }
      ptr.buttons = 0;
      if (ptr.over) {
        ptrEv('pointerout', ptr.over, { relatedTarget: null, button: -1 });
        ptrEv('mouseout', ptr.over, { relatedTarget: null });
      }
      ptr.over = null;
    },
    // Chẩn đoán: gọi từ Web Inspector -> __gfnMouse.stats()
    stats: function () {
      return {
        lock: !!lockEl, pad: mode.pad, kbm: mode.kbm, padOn: padOn, index: padIndex,
        polls: polls, axes: padAx.slice(), buttons: padBtn.join(''), dataChannelSends: dcCount,
        ptr: { x: ptr.x, y: ptr.y, buttons: ptr.buttons, sent: ptr.sent, last: ptr.last, relative: !!lockEl }
      };
    }
  };

  // Cắm tay cầm ảo ngay nếu trang đã sẵn sàng (nếu chưa: DOMContentLoaded / load / config() từ Swift sẽ cắm)
  syncPad();
})();
