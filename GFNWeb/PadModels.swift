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
    static let names: [Int: (String, String)] = [
        0: ("A", "A"), 1: ("B", "B"), 2: ("X", "X"), 3: ("Y", "Y"),
        4: ("LB", "LB"), 5: ("RB", "RB"), 6: ("LT", "LT"), 7: ("RT", "RT"),
        8: ("Back", "Back"), 9: ("Start", "Start"), 10: ("L3 (nhấn cần trái)", "L3"), 11: ("R3 (nhấn cần phải)", "R3"),
        12: ("D-Pad Lên", "D↑"), 13: ("D-Pad Xuống", "D↓"), 14: ("D-Pad Trái", "D←"), 15: ("D-Pad Phải", "D→"),
    ]
    static let lt = 6
}

// MARK: - Hành động của một nút

enum PadAction: Codable, Equatable {
    case mouse(Int)          // 0 = trái (RT), 1 = giữa (R3), 2 = phải (LT)
    case key(KeySpec)
    case releaseLock         // thả chuột để chạm vào menu của GFN
    case pad(Int)            // nút tay cầm Xbox ảo (LB, RB, A, B, X, Y, L3, Start, Back, D-Pad...)
    case toggleKeyboard      // bật / tắt bàn phím ảo của iOS
    case toggleHUD           // ẩn / hiện bộ nút (khi ẩn: chạm tự do vào menu game)

    var title: String {
        switch self {
        case .mouse(let b): return b == 0 ? "Bắn (RT / Chuột trái)" : (b == 2 ? "Ngắm (LT / Chuột phải)" : "R3 (Chuột giữa)")
        case .key(let k): return "Phím " + k.display
        case .releaseLock: return "Thả chuột (mở menu)"
        case .pad(let i): return "Tay cầm: " + (GamepadButton.names[i]?.0 ?? "Nút \(i)")
        case .toggleKeyboard: return "Bật/Tắt bàn phím ảo"
        case .toggleHUD: return "Ẩn/Hiện HUD"
        }
    }

    var defaultLabel: String {
        switch self {
        case .mouse(let b): return b == 0 ? "Bắn" : (b == 2 ? "Ngắm" : "R3")
        case .key(let k): return k.display
        case .releaseLock: return "Menu"
        case .pad(let i): return GamepadButton.names[i]?.1 ?? "\(i)"
        case .toggleKeyboard: return "⌨︎"
        case .toggleHUD: return "HUD"
        }
    }

    /// Đang giữ nút này nghĩa là đang ngắm (LT / chuột phải) -> dùng cho gyro "chỉ khi ngắm"
    var isAim: Bool {
        switch self {
        case .mouse(let b): return b == 2
        case .pad(let i): return i == GamepadButton.lt
        default: return false
        }
    }
}

// MARK: - Danh mục hành động (bảng chọn phân nhóm)

extension PadAction {
    /// Danh sách hành động hay dùng (hiện ngay ở bảng chọn đầu tiên)
    static var presets: [(String, PadAction)] {
        var list: [(String, PadAction)] = [
            ("Chuột trái (bắn)", .mouse(0)),
            ("Chuột phải (ngắm)", .mouse(2)),
            ("Chuột giữa", .mouse(1)),
            ("Space (nhảy)", .key(.space)),
            ("Shift (chạy)", .key(.shift)),
            ("Ctrl (ngồi)", .key(.ctrl)),
        ]
        for ch in ["R", "E", "F", "Q", "C", "V", "G", "X", "Z"] {
            if let k = KeySpec.parse(ch) { list.append(("Phím \(ch)", .key(k))) }
        }
        list.append(("Tab", .key(.tab)))
        list.append(("Alt", .key(.alt)))
        for n in 1...5 {
            if let k = KeySpec.parse("\(n)") { list.append(("Phím \(n)", .key(k))) }
        }
        list.append(("Bật/Tắt bàn phím ảo", .toggleKeyboard))
        list.append(("Ẩn/Hiện HUD", .toggleHUD))
        list.append(("Thả chuột (mở menu GFN)", .releaseLock))
        return list
    }
}

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
            ActionGroup(title: "Tay cầm / Bắn", items: [
                ActionItem(label: "Bắn", detail: "RT / Chuột trái", action: .mouse(0)),
                ActionItem(label: "Ngắm", detail: "LT / Chuột phải", action: .mouse(2)),
                ActionItem(label: "R3", detail: "Chuột giữa", action: .mouse(1)),
                padItem(4, "LB"), padItem(5, "RB"),
                padItem(0, "A"), padItem(1, "B"), padItem(2, "X"), padItem(3, "Y"),
                padItem(10, "L3"), padItem(9, "Start"), padItem(8, "Back"),
                padItem(12, "D-Pad ↑"), padItem(13, "D-Pad ↓"), padItem(14, "D-Pad ←"), padItem(15, "D-Pad →"),
            ]),
            ActionGroup(title: "Phím bổ trợ (Trái / Phải)", items: KeySpec.modifiers.map { keyItem($0) }),
            ActionGroup(title: "Phím điều khiển", items: KeySpec.controls.map { keyItem($0) }),
            ActionGroup(title: "Phím chức năng", items: KeySpec.functionKeys.map { keyItem($0) }),
            ActionGroup(title: "Phím mũi tên", items: KeySpec.arrows.map { keyItem($0) }),
            ActionGroup(title: "Chữ cái A – Z", items: KeySpec.letters.map { keyItem($0) }),
            ActionGroup(title: "Số & dấu câu", items: (KeySpec.digits + KeySpec.punctuation).map { keyItem($0) }),
            ActionGroup(title: "Hệ thống", items: [
                ActionItem(label: "Bàn phím ảo", detail: "Bật / tắt", action: .toggleKeyboard),
                ActionItem(label: "Ẩn/Hiện HUD", detail: "Chạm menu game", action: .toggleHUD),
                ActionItem(label: "Thả chuột", detail: "Mở menu GFN", action: .releaseLock),
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
}

enum GyroMode: String, Codable {
    case off
    case always
    case whileAiming    // chỉ khi đang giữ nút chuột phải (ngắm)
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

    // Joystick đi (WASD)
    var joyX: CGFloat = 0.13
    var joyY: CGFloat = 0.70
    var joySize: CGFloat = 150

    // Vùng vuốt xoay camera (Right Stick Look Pad): tâm (lookX, lookY) và kích thước, tất cả theo tỉ lệ màn hình 0...1
    var lookX: CGFloat = 0.72
    var lookY: CGFloat = 0.46
    var lookWidth: CGFloat = 0.38
    var lookHeight: CGFloat = 0.72

    /// Chạm = chuột: khi game khóa chuột, vùng trống thành touchpad (kéo = di chuyển con trỏ, chạm = click trái)
    var touchMouse = false

    var buttons: [PadButton] = PadSettings.defaultButtons

    /// Giữ vùng xoay camera nằm trọn trong màn hình và không quá nhỏ / quá lớn
    mutating func clampLookPad() {
        lookWidth = min(max(lookWidth, 0.12), 0.9)
        lookHeight = min(max(lookHeight, 0.15), 0.95)
        lookX = min(max(lookX, lookWidth / 2), 1 - lookWidth / 2)
        lookY = min(max(lookY, lookHeight / 2), 1 - lookHeight / 2)
    }

    mutating func resetLookPad() {
        let d = PadSettings()
        lookX = d.lookX; lookY = d.lookY; lookWidth = d.lookWidth; lookHeight = d.lookHeight
    }

    enum CodingKeys: String, CodingKey {
        case enabled, opacity, lookSensitivity, gyroMode, gyroSensitivity, gyroInvertX, gyroInvertY
        case joyX, joyY, joySize, lookX, lookY, lookWidth, lookHeight, touchMouse, buttons
    }

    static var defaultButtons: [PadButton] {
        [
            PadButton(label: "Bắn", action: .mouse(0), x: 0.88, y: 0.58, size: 92),
            PadButton(label: "Ngắm", action: .mouse(2), x: 0.76, y: 0.70, size: 72),
            PadButton(label: "Nhảy", action: .key(.space), x: 0.92, y: 0.82, size: 64),
            PadButton(label: "R", action: .key(KeySpec.parse("R")!), x: 0.66, y: 0.84, size: 56),
            PadButton(label: "Ngồi", action: .key(.ctrl), x: 0.40, y: 0.84, size: 56),
            PadButton(label: "Chạy", action: .key(.shift), x: 0.28, y: 0.48, size: 56),
        ]
    }
}

// Giải mã "dễ tính": cài đặt cũ (chưa có vùng xoay camera) vẫn đọc được, trường thiếu dùng giá trị mặc định
extension PadSettings {
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
        joyX = try c.decodeIfPresent(CGFloat.self, forKey: .joyX) ?? joyX
        joyY = try c.decodeIfPresent(CGFloat.self, forKey: .joyY) ?? joyY
        joySize = try c.decodeIfPresent(CGFloat.self, forKey: .joySize) ?? joySize
        lookX = try c.decodeIfPresent(CGFloat.self, forKey: .lookX) ?? lookX
        lookY = try c.decodeIfPresent(CGFloat.self, forKey: .lookY) ?? lookY
        lookWidth = try c.decodeIfPresent(CGFloat.self, forKey: .lookWidth) ?? lookWidth
        lookHeight = try c.decodeIfPresent(CGFloat.self, forKey: .lookHeight) ?? lookHeight
        touchMouse = try c.decodeIfPresent(Bool.self, forKey: .touchMouse) ?? touchMouse
        buttons = try c.decodeIfPresent([PadButton].self, forKey: .buttons) ?? buttons
        clampLookPad()
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
