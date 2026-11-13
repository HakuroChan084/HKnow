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
        case "ShiftLeft": return "Shift"
        case "ControlLeft": return "Ctrl"
        case "AltLeft": return "Alt"
        case "Escape": return "Esc"
        default: return key.uppercased()
        }
    }

    static let w = KeySpec(key: "w", code: "KeyW", keyCode: 87)
    static let a = KeySpec(key: "a", code: "KeyA", keyCode: 65)
    static let s = KeySpec(key: "s", code: "KeyS", keyCode: 83)
    static let d = KeySpec(key: "d", code: "KeyD", keyCode: 68)
    static let space = KeySpec(key: " ", code: "Space", keyCode: 32)
    static let shift = KeySpec(key: "Shift", code: "ShiftLeft", keyCode: 16)
    static let ctrl = KeySpec(key: "Control", code: "ControlLeft", keyCode: 17)
    static let alt = KeySpec(key: "Alt", code: "AltLeft", keyCode: 18)
    static let tab = KeySpec(key: "Tab", code: "Tab", keyCode: 9)
    static let enter = KeySpec(key: "Enter", code: "Enter", keyCode: 13)
    static let esc = KeySpec(key: "Escape", code: "Escape", keyCode: 27)

    /// Đọc phím từ chữ người dùng gõ: "r", "5", "F5", "space", "shift", "ctrl", "tab", "esc", "up"...
    static func parse(_ raw: String) -> KeySpec? {
        let u = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !u.isEmpty else { return nil }
        switch u {
        case "SPACE": return .space
        case "ENTER", "RETURN": return .enter
        case "TAB": return .tab
        case "SHIFT": return .shift
        case "CTRL", "CONTROL": return .ctrl
        case "ALT": return .alt
        case "ESC", "ESCAPE": return .esc
        case "UP": return KeySpec(key: "ArrowUp", code: "ArrowUp", keyCode: 38)
        case "DOWN": return KeySpec(key: "ArrowDown", code: "ArrowDown", keyCode: 40)
        case "LEFT": return KeySpec(key: "ArrowLeft", code: "ArrowLeft", keyCode: 37)
        case "RIGHT": return KeySpec(key: "ArrowRight", code: "ArrowRight", keyCode: 39)
        default: break
        }
        if u.count == 1, let scalar = u.unicodeScalars.first {
            if scalar.value >= 65 && scalar.value <= 90 {
                return KeySpec(key: u.lowercased(), code: "Key" + u, keyCode: Int(scalar.value))
            }
            if scalar.value >= 48 && scalar.value <= 57 {
                return KeySpec(key: u, code: "Digit" + u, keyCode: Int(scalar.value))
            }
        }
        if u.hasPrefix("F"), let n = Int(u.dropFirst()), n >= 1, n <= 12 {
            return KeySpec(key: "F\(n)", code: "F\(n)", keyCode: 111 + n)
        }
        return nil
    }
}

// MARK: - Hành động của một nút

enum PadAction: Codable, Equatable {
    case mouse(Int)          // 0 = trái, 1 = giữa, 2 = phải
    case key(KeySpec)
    case releaseLock         // thả chuột để chạm vào menu của GFN

    var title: String {
        switch self {
        case .mouse(let b): return b == 0 ? "Chuột trái" : (b == 2 ? "Chuột phải" : "Chuột giữa")
        case .key(let k): return "Phím " + k.display
        case .releaseLock: return "Thả chuột (mở menu)"
        }
    }

    var defaultLabel: String {
        switch self {
        case .mouse(let b): return b == 0 ? "Bắn" : (b == 2 ? "Ngắm" : "Giữa")
        case .key(let k): return k.display
        case .releaseLock: return "Menu"
        }
    }

    /// Danh sách hành động có sẵn khi thêm / đổi nút
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
        list.append(("Thả chuột (mở menu GFN)", .releaseLock))
        return list
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

    var buttons: [PadButton] = PadSettings.defaultButtons

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
