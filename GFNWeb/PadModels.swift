import UIKit

// MARK: - Phím bàn phím

struct KeySpec: Codable, Equatable {
    var key: String      // ví dụ "w", " ", "Shift"
    var code: String     // ví dụ "KeyW", "Space", "ShiftLeft"
    var keyCode: Int     // ví dụ 87

    /// Tên hiển thị ngắn
    var display: String {
        switch code {
        case "Space": return "Space"
        case "ShiftLeft": return "L-Shift"
        case "ShiftRight": return "R-Shift"
        case "ControlLeft": return "L-Ctrl"
        case "ControlRight": return "R-Ctrl"
        case "AltLeft": return "L-Alt"
        case "AltRight": return "R-Alt"
        case "Escape": return "Esc"
        case "Backspace": return "Bksp"
        case "CapsLock": return "Caps"
        case "ArrowUp": return "↑"
        case "ArrowDown": return "↓"
        case "ArrowLeft": return "←"
        case "ArrowRight": return "→"
        default: return key.uppercased()
        }
    }

    static let w = KeySpec(key: "w", code: "KeyW", keyCode: 87)
    static let a = KeySpec(key: "a", code: "KeyA", keyCode: 65)
    static let s = KeySpec(key: "s", code: "KeyS", keyCode: 83)
    static let d = KeySpec(key: "d", code: "KeyD", keyCode: 68)
    static let space = KeySpec(key: " ", code: "Space", keyCode: 32)
    static let shift = KeySpec(key: "Shift", code: "ShiftLeft", keyCode: 16)
    static let shiftR = KeySpec(key: "Shift", code: "ShiftRight", keyCode: 16)
    static let ctrl = KeySpec(key: "Control", code: "ControlLeft", keyCode: 17)
    static let ctrlR = KeySpec(key: "Control", code: "ControlRight", keyCode: 17)
    static let alt = KeySpec(key: "Alt", code: "AltLeft", keyCode: 18)
    static let altR = KeySpec(key: "Alt", code: "AltRight", keyCode: 18)
    static let tab = KeySpec(key: "Tab", code: "Tab", keyCode: 9)
    static let enter = KeySpec(key: "Enter", code: "Enter", keyCode: 13)
    static let esc = KeySpec(key: "Escape", code: "Escape", keyCode: 27)
    static let backspace = KeySpec(key: "Backspace", code: "Backspace", keyCode: 8)
    static let capsLock = KeySpec(key: "CapsLock", code: "CapsLock", keyCode: 20)
    static let up = KeySpec(key: "ArrowUp", code: "ArrowUp", keyCode: 38)
    static let down = KeySpec(key: "ArrowDown", code: "ArrowDown", keyCode: 40)
    static let left = KeySpec(key: "ArrowLeft", code: "ArrowLeft", keyCode: 37)
    static let right = KeySpec(key: "ArrowRight", code: "ArrowRight", keyCode: 39)

    // MARK: Các nhóm phím (dùng cho bảng chọn)

    /// Phím bổ trợ, phân biệt Trái / Phải
    static let modifiers: [KeySpec] = [.shift, .shiftR, .ctrl, .ctrlR, .alt, .altR]

    /// Phím điều khiển
    static let controls: [KeySpec] = [.enter, .esc, .space, .tab, .backspace, .capsLock]

    /// F1 – F12
    static let functionKeys: [KeySpec] = (1...12).map { KeySpec(key: "F\($0)", code: "F\($0)", keyCode: 111 + $0) }

    /// Phím mũi tên
    static let arrows: [KeySpec] = [.up, .down, .left, .right]

    /// A – Z
    static let letters: [KeySpec] = (65...90).map { v in
        let c = String(Character(Unicode.Scalar(UInt8(v))))
        return KeySpec(key: c.lowercased(), code: "Key" + c, keyCode: v)
    }

    /// 0 – 9
    static let digits: [KeySpec] = (0...9).map { KeySpec(key: "\($0)", code: "Digit\($0)", keyCode: 48 + $0) }

    /// Dấu câu thường dùng
    static let punctuation: [KeySpec] = [
        KeySpec(key: "-", code: "Minus", keyCode: 189),
        KeySpec(key: "=", code: "Equal", keyCode: 187),
        KeySpec(key: "[", code: "BracketLeft", keyCode: 219),
        KeySpec(key: "]", code: "BracketRight", keyCode: 221),
        KeySpec(key: ";", code: "Semicolon", keyCode: 186),
        KeySpec(key: "'", code: "Quote", keyCode: 222),
        KeySpec(key: ",", code: "Comma", keyCode: 188),
        KeySpec(key: ".", code: "Period", keyCode: 190),
        KeySpec(key: "/", code: "Slash", keyCode: 191),
        KeySpec(key: "`", code: "Backquote", keyCode: 192),
        KeySpec(key: "\\", code: "Backslash", keyCode: 220),
    ]

    /// Toàn bộ phím đã biết
    static let all: [KeySpec] = modifiers + controls + functionKeys + arrows + letters + digits + punctuation

    /// Đọc phím từ chữ người dùng gõ: "r", "5", "F5", "space", "shift", "ctrl", "tab", "esc", "up", "bksp", "-"...
    static func parse(_ raw: String) -> KeySpec? {
        let u = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !u.isEmpty else { return nil }
        switch u {
        case "SPACE": return .space
        case "ENTER", "RETURN": return .enter
        case "ESC", "ESCAPE": return .esc
        case "UP": return .up
        case "DOWN": return .down
        case "LEFT": return .left
        case "RIGHT": return .right
        case "BACKSPACE", "BKSP": return .backspace
        case "CAPS", "CAPSLOCK": return .capsLock
        default: break
        }
        return all.first {
            $0.code.uppercased() == u || $0.key.uppercased() == u || $0.display.uppercased() == u
        }
    }
}

// MARK: - Nút tay cầm Xbox (chỉ số theo mapping "standard")

enum GamepadButton {
    /// (tên đầy đủ, nhãn ngắn) theo chỉ số nút
    static var names: [Int: (String, String)] { [
        0: ("A", "A"), 1: ("B", "B"), 2: ("X", "X"), 3: ("Y", "Y"),
        4: ("LB", "LB"), 5: ("RB", "RB"), 6: ("LT", "LT"), 7: ("RT", "RT"),
        8: ("Back", "Back"), 9: ("Start", "Start"), 10: (L("L3 (nhấn cần trái)"), "L3"), 11: (L("R3 (nhấn cần phải)"), "R3"),
        12: (L("D-Pad Lên"), "D↑"), 13: (L("D-Pad Xuống"), "D↓"), 14: (L("D-Pad Trái"), "D←"), 15: (L("D-Pad Phải"), "D→"),
    ] }
    static let lt = 6
}

// MARK: - Hành động của một nút

enum PadAction: Codable, Equatable {
    case mouse(Int)          // CHUỘT thật: 0 = trái, 1 = giữa, 2 = phải (chỉ dùng cho chế độ Chuột + Phím)
    case key(KeySpec)
    case releaseLock         // thả chuột để chạm vào menu của GFN
    case pad(Int)            // nút tay cầm Xbox ảo (LB, RB, A, B, X, Y, L3, Start, Back, D-Pad...)
    case toggleKeyboard      // bật / tắt bàn phím ảo của iOS
    case toggleHUD           // ẩn / hiện bộ nút (khi ẩn: chạm tự do vào menu game)
    case fireAim             // Bắn + Ngắm CÙNG LÚC bằng một nút (chuột trái + chuột phải / RT + LT): chơi 1 tay hoặc 3 tay

    var title: String {
        switch self {
        case .mouse(let b): return b == 0 ? L("Chuột trái") : (b == 2 ? L("Chuột phải") : L("Chuột giữa"))
        case .key(let k): return L("Phím ") + k.display
        case .releaseLock: return L("Thả chuột (mở menu)")
        case .pad(let i): return L("Tay cầm: ") + (GamepadButton.names[i]?.0 ?? String(format: L("Nút %d"), i))
        case .toggleKeyboard: return L("Bật/Tắt bàn phím ảo")
        case .toggleHUD: return L("Ẩn/Hiện HUD")
        case .fireAim: return L("Bắn + Ngắm (cùng lúc)")
        }
    }

    var defaultLabel: String {
        switch self {
        case .mouse(let b): return b == 0 ? "LMB" : (b == 2 ? "RMB" : "MMB")
        case .key(let k): return k.display
        case .releaseLock: return "Menu"
        case .pad(let i): return GamepadButton.names[i]?.1 ?? "\(i)"
        case .toggleKeyboard: return "⌨︎"
        case .toggleHUD: return "HUD"
        case .fireAim: return L("Bắn+Ngắm")
        }
    }

    /// Đang giữ nút này nghĩa là đang ngắm (LT / chuột phải) -> dùng cho gyro "chỉ khi ngắm"
    var isAim: Bool {
        switch self {
        case .mouse(let b): return b == 2
        case .pad(let i): return i == GamepadButton.lt
        case .fireAim: return true
        default: return false
        }
    }

    /// Mặc định có cho vuốt xoay camera bằng chính ngón tay đang giữ nút không
    /// (Bắn, Ngắm, R3, LB / RB / LT / RT, phím G ném lựu đạn).
    var defaultAllowDragLook: Bool {
        switch self {
        case .mouse, .fireAim: return true
        case .pad(let i): return [4, 5, 6, 7].contains(i)
        case .key(let k): return k.code == "KeyG"
        default: return false
        }
    }
}

// MARK: - Danh mục hành động (bảng chọn phân nhóm)

struct ActionItem {
    let label: String       // chữ lớn trên ô
    let detail: String?     // chữ nhỏ bên dưới
    let action: PadAction
}

struct ActionGroup {
    let title: String
    let items: [ActionItem]
}

extension PadAction {
    static var catalog: [ActionGroup] {
        func keyItem(_ k: KeySpec, _ detail: String? = nil) -> ActionItem {
            ActionItem(label: k.display, detail: detail, action: .key(k))
        }
        func padItem(_ i: Int, _ label: String, _ detail: String? = nil) -> ActionItem {
            ActionItem(label: label, detail: detail, action: .pad(i))
        }

        return [
            ActionGroup(title: L("Tay cầm (Xbox)"), items: [
                padItem(7, "RT", L("Bắn")), padItem(6, "LT", L("Ngắm")),
                ActionItem(label: L("Bắn+Ngắm"), detail: L("RT + LT cùng lúc"), action: .fireAim),
                padItem(4, "LB"), padItem(5, "RB"),
                padItem(0, "A"), padItem(1, "B"), padItem(2, "X"), padItem(3, "Y"),
                padItem(10, "L3"), padItem(11, "R3"), padItem(9, "Start"), padItem(8, "Back"),
                padItem(12, "D-Pad ↑"), padItem(13, "D-Pad ↓"), padItem(14, "D-Pad ←"), padItem(15, "D-Pad →"),
            ]),
            ActionGroup(title: L("Chuột (chế độ Chuột + Phím)"), items: [
                ActionItem(label: L("Chuột trái"), detail: L("Bắn"), action: .mouse(0)),
                ActionItem(label: L("Chuột phải"), detail: L("Ngắm"), action: .mouse(2)),
                ActionItem(label: L("Chuột giữa"), detail: nil, action: .mouse(1)),
                ActionItem(label: L("Bắn+Ngắm"), detail: L("Trái + phải cùng lúc"), action: .fireAim),
            ]),
            ActionGroup(title: L("Phím bổ trợ (Trái / Phải)"), items: KeySpec.modifiers.map { keyItem($0) }),
            ActionGroup(title: L("Phím điều khiển"), items: KeySpec.controls.map { keyItem($0) }),
            ActionGroup(title: L("Phím chức năng"), items: KeySpec.functionKeys.map { keyItem($0) }),
            ActionGroup(title: L("Phím mũi tên"), items: KeySpec.arrows.map { keyItem($0) }),
            ActionGroup(title: L("Chữ cái A – Z"), items: KeySpec.letters.map { keyItem($0) }),
            ActionGroup(title: L("Số & dấu câu"), items: (KeySpec.digits + KeySpec.punctuation).map { keyItem($0) }),
            ActionGroup(title: L("Hệ thống"), items: [
                ActionItem(label: L("Bàn phím ảo"), detail: L("Bật / tắt"), action: .toggleKeyboard),
                ActionItem(label: L("Ẩn/Hiện HUD"), detail: L("Chạm menu game"), action: .toggleHUD),
                ActionItem(label: L("Thả chuột"), detail: L("Mở menu GFN"), action: .releaseLock),
            ]),
        ]
    }
}

// MARK: - Nút bấm

struct PadButton: Codable, Identifiable {
    var id = UUID()
    var label: String
    var action: PadAction
    var x: CGFloat      // vị trí tâm nút, 0...1 theo chiều ngang màn hình
    var y: CGFloat      // 0...1 theo chiều dọc
    var size: CGFloat   // đường kính (point)
    /// Giữ nút + kéo ngón tay = vừa giữ lệnh vừa xoay camera (ghìm tâm / xoay ngắm bằng ngón đang giữ nút)
    var allowDragLook: Bool

    init(label: String, action: PadAction, x: CGFloat, y: CGFloat, size: CGFloat, allowDragLook: Bool? = nil) {
        self.label = label
        self.action = action
        self.x = x
        self.y = y
        self.size = size
        self.allowDragLook = allowDragLook ?? action.defaultAllowDragLook
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, action, x, y, size, allowDragLook
    }

    /// Đọc được cả dữ liệu đã lưu từ bản cũ (chưa có allowDragLook)
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        label = try c.decode(String.self, forKey: .label)
        action = try c.decode(PadAction.self, forKey: .action)
        x = try c.decode(CGFloat.self, forKey: .x)
        y = try c.decode(CGFloat.self, forKey: .y)
        size = try c.decode(CGFloat.self, forKey: .size)
        allowDragLook = try c.decodeIfPresent(Bool.self, forKey: .allowDragLook) ?? action.defaultAllowDragLook
    }
}

enum GyroMode: String, Codable {
    case off
    case always
    case whileAiming    // chỉ khi đang giữ nút chuột phải (ngắm)
}

/// Hai chế độ chạm, đổi nhanh bằng công tắc ở mép trên màn hình
enum ControlMode: Int {
    case hud = 0        // Chiến đấu: hiện bộ nút ảo, vùng trống để vuốt xoay camera
    case mouse = 1      // Chuột / Launcher: ẩn nút ảo, chạm / kéo = rê và bấm chuột trong cửa sổ Steam / Epic...
}

/// Cách chạm khi ở chế độ Chuột / Launcher
enum MouseTouchStyle: String, Codable {
    case virtualCursor  // con trỏ ảo: kéo ngón tay để rê chuột, chạm = click, giữ = kéo thả, 2 ngón = chuột phải / cuộn
    case native         // chạm gốc: chạm thẳng xuống WKWebView (WebKit tự đổi tap thành click)
}

// MARK: - Cài đặt toàn bộ

struct PadSettings: Codable {
    var enabled = true
    var opacity: CGFloat = 0.6
    var lookSensitivity: CGFloat = 1.0
    var gyroMode: GyroMode = .off
    var gyroSensitivity: CGFloat = 1.0
    var gyroInvertX = false
    var gyroInvertY = false

    // Hai bố cục TÁCH BIỆT: "Tay cầm" và "Chuột + Phím". Mọi chỗ dùng buttons / joyX / joyY / joySize
    // tự trỏ vào bố cục của chế độ đang chọn (PadSettings.kbmActive do WebViewController đặt).
    var padLayout = PadLayout.defaultPad
    var kbmLayout = PadLayout.defaultKBM

    /// true = đang dùng chế độ Chuột + Phím (bố cục riêng)
    static var kbmActive = false

    var buttons: [PadButton] {
        get { PadSettings.kbmActive ? kbmLayout.buttons : padLayout.buttons }
        set { if PadSettings.kbmActive { kbmLayout.buttons = newValue } else { padLayout.buttons = newValue } }
    }
    var joyX: CGFloat {
        get { PadSettings.kbmActive ? kbmLayout.joyX : padLayout.joyX }
        set { if PadSettings.kbmActive { kbmLayout.joyX = newValue } else { padLayout.joyX = newValue } }
    }
    var joyY: CGFloat {
        get { PadSettings.kbmActive ? kbmLayout.joyY : padLayout.joyY }
        set { if PadSettings.kbmActive { kbmLayout.joyY = newValue } else { padLayout.joyY = newValue } }
    }
    var joySize: CGFloat {
        get { PadSettings.kbmActive ? kbmLayout.joySize : padLayout.joySize }
        set { if PadSettings.kbmActive { kbmLayout.joySize = newValue } else { padLayout.joySize = newValue } }
    }

    /// Đặt lại bố cục của chế độ đang chọn (không đụng bố cục kia)
    mutating func resetActiveLayout() {
        if PadSettings.kbmActive { kbmLayout = .defaultKBM } else { padLayout = .defaultPad }
    }

    // Chế độ Chuột / Launcher
    // Mặc định "Chạm gốc": cú chạm thật (isTrusted) đi thẳng vào game, GFN tự đổi thành click chuột
    var mouseStyle: MouseTouchStyle = .native

    /// Chế độ Chuột + Phím: cách gửi nút bắn / ngắm vào game. 0 = cả click chuột lẫn RT/LT, 1 = chỉ click chuột, 2 = chỉ RT/LT
    var kbmFire = 0
    /// Đảo chuột trái <-> phải (để thử khi game hiểu ngược nút)
    var swapMouse = false
    /// Chế độ Chuột + Phím: bấm LMB / RMB / MMB ảo thì GỬI KÈM phím P / 0 / I (game không nhận click giả, nhưng nhận phím:
    /// vào cài đặt game gán phím phụ Bắn = P, Ngắm = 0, Chuột giữa = I)
    var mouseKeyAlias = true

    init() {}

    private enum CodingKeys: String, CodingKey {
        case enabled, opacity, lookSensitivity, gyroMode, gyroSensitivity, gyroInvertX, gyroInvertY
        case joyX, joyY, joySize, buttons       // bố cục Tay cầm (giữ khóa cũ để đọc được dữ liệu đã lưu)
        case kbmLayout
        case kbmFire, swapMouse, mouseKeyAlias
        case splitV2            // đã tách riêng nút chuột và nút tay cầm
        case fireEnsured        // đã đảm bảo bố cục Chuột + Phím có nút Chuột trái (bắn)
        case comboEnsured       // đã thêm nút Bắn + Ngắm vào bố cục Chuột + Phím
        case mouseStyle = "mouseStyleV2"      // khóa mới: bỏ lựa chọn cũ (Con trỏ ảo) một lần để dùng mặc định Chạm gốc
    }

    /// Mọi trường đều tùy chọn: dữ liệu lưu từ bản cũ vẫn đọc được, trường mới lấy giá trị mặc định
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
        opacity = try c.decodeIfPresent(CGFloat.self, forKey: .opacity) ?? opacity
        lookSensitivity = try c.decodeIfPresent(CGFloat.self, forKey: .lookSensitivity) ?? lookSensitivity
        gyroMode = try c.decodeIfPresent(GyroMode.self, forKey: .gyroMode) ?? gyroMode
        gyroSensitivity = try c.decodeIfPresent(CGFloat.self, forKey: .gyroSensitivity) ?? gyroSensitivity
        gyroInvertX = try c.decodeIfPresent(Bool.self, forKey: .gyroInvertX) ?? gyroInvertX
        gyroInvertY = try c.decodeIfPresent(Bool.self, forKey: .gyroInvertY) ?? gyroInvertY
        padLayout.joyX = try c.decodeIfPresent(CGFloat.self, forKey: .joyX) ?? padLayout.joyX
        padLayout.joyY = try c.decodeIfPresent(CGFloat.self, forKey: .joyY) ?? padLayout.joyY
        padLayout.joySize = try c.decodeIfPresent(CGFloat.self, forKey: .joySize) ?? padLayout.joySize
        padLayout.buttons = try c.decodeIfPresent([PadButton].self, forKey: .buttons) ?? padLayout.buttons
        kbmLayout = try c.decodeIfPresent(PadLayout.self, forKey: .kbmLayout) ?? kbmLayout
        kbmFire = try c.decodeIfPresent(Int.self, forKey: .kbmFire) ?? kbmFire
        swapMouse = try c.decodeIfPresent(Bool.self, forKey: .swapMouse) ?? swapMouse
        mouseKeyAlias = try c.decodeIfPresent(Bool.self, forKey: .mouseKeyAlias) ?? mouseKeyAlias
        if !(try c.decodeIfPresent(Bool.self, forKey: .fireEnsured) ?? false) {
            // Bố cục Chuột + Phím đã chỉnh sửa mà không còn nút Chuột trái thì không thể bắn: thêm lại một nút Bắn (1 lần)
            let hasFire = kbmLayout.buttons.contains { b in
                if case .mouse(0) = b.action { return true } else { return false }
            }
            if !hasFire {
                kbmLayout.buttons.append(PadButton(label: "Bắn", action: .mouse(0), x: 0.88, y: 0.62, size: 76))
            }
        }
        if !(try c.decodeIfPresent(Bool.self, forKey: .comboEnsured) ?? false) {
            // Thêm 1 lần nút Bắn + Ngắm (bắn + ADS cùng lúc) vào bố cục Chuột + Phím đã có
            let has = kbmLayout.buttons.contains { $0.action == .fireAim }
            if !has {
                kbmLayout.buttons.append(PadButton(label: "Bắn+Ngắm", action: .fireAim, x: 0.74, y: 0.58, size: 64))
            }
        }
        if !(try c.decodeIfPresent(Bool.self, forKey: .splitV2) ?? false) {
            // Dữ liệu cũ: nút "Bắn / Ngắm / R3" kiểu chuột trong bố cục Tay cầm -> đổi thành RT / LT / R3 của tay cầm
            padLayout.buttons = padLayout.buttons.map { b in
                var b = b
                if case .mouse(let n) = b.action { b.action = .pad(n == 0 ? 7 : (n == 2 ? 6 : 11)) }
                return b
            }
        }
        mouseStyle = try c.decodeIfPresent(MouseTouchStyle.self, forKey: .mouseStyle) ?? mouseStyle
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(opacity, forKey: .opacity)
        try c.encode(lookSensitivity, forKey: .lookSensitivity)
        try c.encode(gyroMode, forKey: .gyroMode)
        try c.encode(gyroSensitivity, forKey: .gyroSensitivity)
        try c.encode(gyroInvertX, forKey: .gyroInvertX)
        try c.encode(gyroInvertY, forKey: .gyroInvertY)
        try c.encode(padLayout.joyX, forKey: .joyX)
        try c.encode(padLayout.joyY, forKey: .joyY)
        try c.encode(padLayout.joySize, forKey: .joySize)
        try c.encode(padLayout.buttons, forKey: .buttons)
        try c.encode(kbmLayout, forKey: .kbmLayout)
        try c.encode(kbmFire, forKey: .kbmFire)
        try c.encode(swapMouse, forKey: .swapMouse)
        try c.encode(mouseKeyAlias, forKey: .mouseKeyAlias)
        try c.encode(true, forKey: .splitV2)
        try c.encode(true, forKey: .fireEnsured)
        try c.encode(true, forKey: .comboEnsured)
        try c.encode(mouseStyle, forKey: .mouseStyle)
    }
}

/// Một bố cục: joystick đi + các nút
struct PadLayout: Codable {
    var joyX: CGFloat = 0.13
    var joyY: CGFloat = 0.70
    var joySize: CGFloat = 150
    var buttons: [PadButton]

    /// Bố cục Tay cầm (nút ảo Xbox: Bắn = RT, Ngắm = LT...)
    static var defaultPad: PadLayout {
        PadLayout(buttons: [
            PadButton(label: "Bắn", action: .pad(7), x: 0.88, y: 0.58, size: 92),
            PadButton(label: "Ngắm", action: .pad(6), x: 0.76, y: 0.70, size: 72),
            PadButton(label: "Nhảy", action: .pad(0), x: 0.92, y: 0.82, size: 64),
            PadButton(label: "Nạp", action: .pad(2), x: 0.66, y: 0.84, size: 56),
            PadButton(label: "Ngồi", action: .pad(1), x: 0.40, y: 0.84, size: 56),
            PadButton(label: "Chạy", action: .pad(10), x: 0.28, y: 0.48, size: 56),
        ])
    }

    /// Bố cục Chuột + Phím (joystick = W A S D, vuốt = chuột, nút = phím / chuột)
    static var defaultKBM: PadLayout {
        func key(_ s: String) -> PadAction { .key(KeySpec.parse(s)!) }
        return PadLayout(buttons: [
            PadButton(label: "Bắn", action: .mouse(0), x: 0.88, y: 0.58, size: 92),
            PadButton(label: "Ngắm", action: .mouse(2), x: 0.76, y: 0.70, size: 72),
            PadButton(label: "Nhảy", action: .key(.space), x: 0.92, y: 0.82, size: 64),
            PadButton(label: "R", action: key("R"), x: 0.66, y: 0.84, size: 56),
            PadButton(label: "Ngồi", action: .key(.ctrl), x: 0.40, y: 0.84, size: 56),
            PadButton(label: "Chạy", action: .key(.shift), x: 0.28, y: 0.48, size: 56),
            PadButton(label: "E", action: key("E"), x: 0.80, y: 0.40, size: 52),
            PadButton(label: "F", action: key("F"), x: 0.70, y: 0.52, size: 52),
            PadButton(label: "Q", action: key("Q"), x: 0.20, y: 0.40, size: 48),
            PadButton(label: "Bắn+Ngắm", action: .fireAim, x: 0.74, y: 0.58, size: 64),
            PadButton(label: "1", action: key("1"), x: 0.40, y: 0.16, size: 46),
            PadButton(label: "2", action: key("2"), x: 0.47, y: 0.16, size: 46),
            PadButton(label: "3", action: key("3"), x: 0.54, y: 0.16, size: 46),
        ])
    }
}

// MARK: - Lưu trữ

final class PadStore {
    static let shared = PadStore()

    var settings: PadSettings
    private let defaultsKey = "gfnweb.padSettings.v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode(PadSettings.self, from: data) {
            settings = saved
        } else {
            settings = PadSettings()
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
