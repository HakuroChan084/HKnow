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
  var mode = { pad: true, kbm: false, tm: false };   // mặc định dùng tay cầm; Swift sẽ gửi lại qua config()

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

  // Chỉ ở chế độ chuột-phím tổng hợp (kbm) mới chặn sự kiện chuột "thật" khi đang khóa, để khỏi bị nhân đôi.
  // Ở chế độ tay cầm KHÔNG chặn gì: vùng chạm xuyên xuống trang (menu, chọn súng, Settings) phải bấm được.
  // (Cảm ứng ở nút / joystick / vùng xoay camera đã bị lớp điều khiển native nuốt từ trước.)
  ['mousemove', 'mousedown', 'mouseup', 'click', 'dblclick', 'auxclick', 'contextmenu',
   'pointermove', 'pointerdown', 'pointerup'].forEach(function (t) {
    window.addEventListener(t, function (e) {
      if (lockEl && mode.kbm && e.isTrusted) { e.stopImmediatePropagation(); e.preventDefault(); }
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

  // ===== Chạm = chuột: chạm lên khung hình stream (video/canvas) => sự kiện chuột (pointerType 'mouse') =====
  // Dùng cho launcher / menu của game (cần con trỏ). Cảm ứng thật bị chặn (preventDefault) để không bị nhân đôi.
  var tmS = { id: null, down: false, sx: 0, sy: 0, lx: 0, ly: 0, el: null, rel: false };
  function isStreamEl(el) { return !!el && (el.tagName === 'VIDEO' || el.tagName === 'CANVAS'); }
  function tmEv(type, el, x, y, button, buttons) {
    var init = {
      bubbles: true, cancelable: true, composed: true, view: window,
      clientX: x, clientY: y, screenX: x, screenY: y, button: button, buttons: buttons
    };
    var ev;
    if (type.indexOf('pointer') === 0) {
      init.pointerId = 1; init.pointerType = 'mouse'; init.isPrimary = true;
      ev = new PointerEvent(type, init);
    } else {
      ev = new MouseEvent(type, init);
    }
    el.dispatchEvent(ev);
  }
  function tmMove(el, x, y, buttons) { tmEv('pointermove', el, x, y, -1, buttons); tmEv('mousemove', el, x, y, -1, buttons); }
  function tmDown(el, x, y) { tmEv('pointerdown', el, x, y, 0, 1); tmEv('mousedown', el, x, y, 0, 1); }
  function tmUp(el, x, y) { tmEv('pointerup', el, x, y, 0, 0); tmEv('mouseup', el, x, y, 0, 0); }
  function tmFind(list) {
    for (var i = 0; i < list.length; i++) if (list[i].identifier === tmS.id) return list[i];
    return null;
  }
  window.addEventListener('touchstart', function (e) {
    if (!mode.tm || tmS.id !== null) return;
    var t = e.changedTouches && e.changedTouches[0];
    if (!t) return;
    var el = (e.composedPath && e.composedPath()[0]) || e.target;
    if (!lockEl && !isStreamEl(el)) return;          // ngoài khung stream: để trang tự xử lý
    tmS.id = t.identifier; tmS.down = false;
    tmS.sx = tmS.lx = t.clientX; tmS.sy = tmS.ly = t.clientY;
    tmS.rel = !!lockEl; tmS.el = lockEl || el;
    e.preventDefault();
    if (!tmS.rel) tmMove(tmS.el, t.clientX, t.clientY, 0);      // rê con trỏ tới chỗ chạm trước
  }, { capture: true, passive: false });
  window.addEventListener('touchmove', function (e) {
    if (tmS.id === null) return;
    var t = tmFind(e.changedTouches);
    if (!t) return;
    e.preventDefault();
    if (tmS.rel) {                                   // game đang khóa chuột: kéo = di chuyển tương đối
      var dx = t.clientX - tmS.lx, dy = t.clientY - tmS.ly;
      tmS.lx = t.clientX; tmS.ly = t.clientY;
      if (dx || dy) { tmEv('pointermove', tmS.el, t.clientX, t.clientY, -1, 0); window.__gfnMouse.tmove(dx * 1.6, dy * 1.6); }
      return;
    }
    if (!tmS.down && Math.hypot(t.clientX - tmS.sx, t.clientY - tmS.sy) > 10) {
      tmS.down = true;                               // kéo: nhấn giữ chuột ở chỗ bắt đầu (thanh trượt, kéo thả)
      tmDown(tmS.el, tmS.sx, tmS.sy);
    }
    if (tmS.down) tmMove(tmS.el, t.clientX, t.clientY, 1);
    tmS.lx = t.clientX; tmS.ly = t.clientY;
  }, { capture: true, passive: false });
  function tmEnd(e) {
    if (tmS.id === null) return;
    var t = tmFind(e.changedTouches);
    if (!t) return;
    e.preventDefault();
    var el = tmS.el, rel = tmS.rel, wasDown = tmS.down;
    tmS.id = null; tmS.down = false;
    if (rel) {
      if (e.type === 'touchend' && Math.hypot(t.clientX - tmS.sx, t.clientY - tmS.sy) < 10) {
        window.__gfnMouse.tbutton(0, true);
        setTimeout(function () { window.__gfnMouse.tbutton(0, false); }, 50);
      }
      return;
    }
    if (wasDown) { tmUp(el, t.clientX, t.clientY); return; }
    if (e.type !== 'touchend') return;
    tmDown(el, t.clientX, t.clientY);                // chạm nhanh = click trái
    setTimeout(function () {
      tmUp(el, t.clientX, t.clientY);
      tmEv('click', el, t.clientX, t.clientY, 0, 0);
    }, 50);
  }
  window.addEventListener('touchend', tmEnd, { capture: true, passive: false });
  window.addEventListener('touchcancel', tmEnd, { capture: true, passive: false });

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
      mode.tm = !!(c && c.tm);
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
    // Chạm = chuột: di chuyển / click chuột tổng hợp trên phần tử đang khóa, không phụ thuộc chế độ nhập liệu
    tmove: function (dx, dy) {
      if (!lockEl) return;
      fire('pointermove', { movementX: dx, movementY: dy });
      fire('mousemove', { movementX: dx, movementY: dy });
    },
    tbutton: function (b, down) {
      if (!lockEl) return;
      var bit = b === 0 ? 1 : b === 2 ? 2 : 4;
      if (down) buttonsMask |= bit; else buttonsMask &= ~bit;
      ensureFocus();
      fire(down ? 'pointerdown' : 'pointerup', { button: b });
      fire(down ? 'mousedown' : 'mouseup', { button: b });
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
