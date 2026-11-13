import UIKit

// MARK: - Nút tròn

final class PadButtonView: UIView {
    private let label = UILabel()
    private var pressed = false

    var editingStyle = false { didSet { updateStyle() } }

    init(model: PadButton) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        layer.borderWidth = 2
        label.textAlignment = .center
        label.textColor = .white
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        label.font = .boldSystemFont(ofSize: 15)
        addSubview(label)
        apply(model)
        updateStyle()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func apply(_ model: PadButton) { label.text = model.label }

    func setPressed(_ value: Bool) {
        pressed = value
        updateStyle()
    }

    private func updateStyle() {
        backgroundColor = UIColor.white.withAlphaComponent(pressed ? 0.5 : 0.16)
        layer.borderColor = (editingStyle ? UIColor.systemYellow : UIColor.white.withAlphaComponent(0.75)).cgColor
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.width / 2
        label.frame = bounds.insetBy(dx: 6, dy: 6)
    }
}

// MARK: - Joystick đi (WASD)

final class JoystickView: UIView {
    private let knob = UIView()
    private(set) var offset = CGPoint.zero      // độ lệch của núm (point)

    var editingStyle = false { didSet { updateStyle() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        layer.borderWidth = 2
        knob.backgroundColor = UIColor.white.withAlphaComponent(0.45)
        addSubview(knob)
        updateStyle()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var radius: CGFloat { bounds.width / 2 }

    func setOffset(_ value: CGPoint) {
        offset = value
        setNeedsLayout()
    }

    private func updateStyle() {
        backgroundColor = UIColor.white.withAlphaComponent(0.10)
        layer.borderColor = (editingStyle ? UIColor.systemYellow : UIColor.white.withAlphaComponent(0.6)).cgColor
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.width / 2
        let k = bounds.width * 0.42
        knob.bounds = CGRect(x: 0, y: 0, width: k, height: k)
        knob.layer.cornerRadius = k / 2
        knob.center = CGPoint(x: bounds.midX + offset.x, y: bounds.midY + offset.y)
    }
}

// MARK: - Lớp điều khiển phủ lên WebView

final class ControllerOverlayView: UIView {

    // Gửi ra ngoài
    var onLook: ((CGFloat, CGFloat) -> Void)?
    var onAction: ((PadAction, Bool) -> Void)?
    /// Độ lệch joystick đi đã chuẩn hóa: x, y trong [-1, 1], y dương = kéo xuống (dùng cho cần gạt trái của tay cầm ảo)
    var onJoystick: ((CGFloat, CGFloat) -> Void)?
    var onEditButton: ((UUID, UIView) -> Void)?
    var onEditJoystick: ((UIView) -> Void)?

    /// Đang giữ nút chuột phải (dùng cho gyro "chỉ khi ngắm")
    private(set) var aimHeld = false

    /// true = chạm ra ngoài các nút / joystick thì cảm ứng đi xuyên xuống trang web (dùng ngoài game)
    var passthroughOutsideControls = false

    /// true = hiện phản hồi trực quan (chấm theo ngón tay, chữ báo thao tác) để thử cảm ứng ngoài game
    var feedback = false {
        didSet {
            if !feedback { lookDot.isHidden = true; flashLabel.isHidden = true }
        }
    }

    var editing = false {
        didSet {
            guard oldValue != editing else { return }
            reset(notify: true)
            buttonViews.values.forEach { $0.editingStyle = editing }
            joystick.editingStyle = editing
            hint.isHidden = !editing
        }
    }

    private enum Role {
        case look
        case joystick
        case button(UUID)
        case editButton(UUID)
        case editJoystick
    }

    private var buttonViews: [UUID: PadButtonView] = [:]
    private let joystick = JoystickView()
    private let hint = UILabel()
    private let lookDot = UIView()
    private let flashLabel = UILabel()
    private var lookTotal = CGPoint.zero

    private var roles: [UITouch: Role] = [:]
    private var startPoints: [UITouch: CGPoint] = [:]
    private var dragged: Set<UITouch> = []
    private var heldJoyCodes: Set<String> = []

    private let joyKeys: [String: KeySpec] = [
        "KeyW": .w, "KeyA": .a, "KeyS": .s, "KeyD": .d,
    ]

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = true
        addSubview(joystick)

        hint.text = "Chế độ chỉnh sửa: kéo để di chuyển • chạm vào nút để sửa / xóa"
        hint.textColor = .systemYellow
        hint.font = .boldSystemFont(ofSize: 14)
        hint.textAlignment = .center
        hint.isHidden = true
        hint.isUserInteractionEnabled = false
        addSubview(hint)

        lookDot.bounds = CGRect(x: 0, y: 0, width: 36, height: 36)
        lookDot.layer.cornerRadius = 18
        lookDot.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.45)
        lookDot.layer.borderWidth = 2
        lookDot.layer.borderColor = UIColor.white.withAlphaComponent(0.8).cgColor
        lookDot.isUserInteractionEnabled = false
        lookDot.isHidden = true
        addSubview(lookDot)

        flashLabel.textColor = .white
        flashLabel.font = .boldSystemFont(ofSize: 15)
        flashLabel.textAlignment = .center
        flashLabel.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        flashLabel.layer.cornerRadius = 8
        flashLabel.clipsToBounds = true
        flashLabel.isUserInteractionEnabled = false
        flashLabel.isHidden = true
        addSubview(flashLabel)
    }

    // MARK: Nhận cảm ứng

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, isUserInteractionEnabled else { return nil }
        // Chuột / trackpad luôn đi xuyên xuống trang web (trừ lúc chỉnh sửa bố cục)
        if !editing, let t = event?.allTouches?.first, t.type == .indirectPointer { return nil }
        if passthroughOutsideControls, !editing, buttonID(at: point) == nil, !joystickHit(point) { return nil }
        return super.hitTest(point, with: event)
    }

    // MARK: Phản hồi trực quan

    private func flash(_ text: String) {
        guard feedback else { return }
        flashLabel.text = "  \(text)  "
        flashLabel.sizeToFit()
        flashLabel.isHidden = false
        setNeedsLayout()
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(hideFlash), object: nil)
        perform(#selector(hideFlash), with: nil, afterDelay: 0.9)
    }

    @objc private func hideFlash() { flashLabel.isHidden = true }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: Dựng giao diện từ cài đặt

    func reload() {
        let s = PadStore.shared.settings
        let ids = Set(s.buttons.map { $0.id })
        for (id, view) in buttonViews where !ids.contains(id) {
            view.removeFromSuperview()
            buttonViews[id] = nil
        }
        for b in s.buttons {
            if let view = buttonViews[b.id] {
                view.apply(b)
            } else {
                let view = PadButtonView(model: b)
                view.editingStyle = editing
                addSubview(view)
                buttonViews[b.id] = view
            }
        }
        bringSubviewToFront(hint)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let s = PadStore.shared.settings
        for b in s.buttons {
            guard let view = buttonViews[b.id] else { continue }
            view.bounds = CGRect(x: 0, y: 0, width: b.size, height: b.size)
            view.center = CGPoint(x: b.x * bounds.width, y: b.y * bounds.height)
        }
        joystick.bounds = CGRect(x: 0, y: 0, width: s.joySize, height: s.joySize)
        joystick.center = CGPoint(x: s.joyX * bounds.width, y: s.joyY * bounds.height)
        hint.frame = CGRect(x: 0, y: safeAreaInsets.top + 12, width: bounds.width, height: 24)
        let fw = max(flashLabel.bounds.width, 10)
        flashLabel.frame = CGRect(x: (bounds.width - fw) / 2, y: safeAreaInsets.top + 44, width: fw, height: 28)
    }

    // MARK: Reset

    func reset(notify: Bool) {
        if notify {
            for code in heldJoyCodes {
                if let spec = joyKeys[code] { onAction?(.key(spec), false) }
            }
            for (_, role) in roles {
                if case .button(let id) = role, let m = model(id) { onAction?(m.action, false) }
            }
        }
        heldJoyCodes.removeAll()
        roles.removeAll()
        startPoints.removeAll()
        dragged.removeAll()
        aimHeld = false
        buttonViews.values.forEach { $0.setPressed(false) }
        joystick.setOffset(.zero)
        if notify { onJoystick?(0, 0) }
        lookDot.isHidden = true
        lookTotal = .zero
    }

    // MARK: Tìm phần tử dưới ngón tay

    private func model(_ id: UUID) -> PadButton? {
        PadStore.shared.settings.buttons.first { $0.id == id }
    }

    private func buttonID(at p: CGPoint) -> UUID? {
        for b in PadStore.shared.settings.buttons.reversed() {
            guard let view = buttonViews[b.id] else { continue }
            if hypot(p.x - view.center.x, p.y - view.center.y) <= b.size / 2 + 8 { return b.id }
        }
        return nil
    }

    private func joystickHit(_ p: CGPoint) -> Bool {
        hypot(p.x - joystick.center.x, p.y - joystick.center.y) <= joystick.radius * 1.3
    }

    private func recomputeAim() {
        var held = false
        for (_, role) in roles {
            if case .button(let id) = role, let m = model(id), case .mouse(2) = m.action { held = true }
        }
        aimHeld = held
    }

    // MARK: Joystick

    private func moveJoystick(to p: CGPoint) {
        let dx = p.x - joystick.center.x
        let dy = p.y - joystick.center.y
        let r = joystick.radius
        let len = hypot(dx, dy)
        let scale = len > r ? r / len : 1
        joystick.setOffset(CGPoint(x: dx * scale, y: dy * scale))
        onJoystick?(joystick.offset.x / max(r, 1), joystick.offset.y / max(r, 1))
        updateJoystickKeys()
    }

    private func updateJoystickKeys() {
        let r = max(joystick.radius, 1)
        let nx = joystick.offset.x / r
        let ny = joystick.offset.y / r
        var want: Set<String> = []
        if ny < -0.35 { want.insert("KeyW") }
        if ny > 0.35 { want.insert("KeyS") }
        if nx < -0.35 { want.insert("KeyA") }
        if nx > 0.35 { want.insert("KeyD") }
        for code in want.subtracting(heldJoyCodes) {
            if let spec = joyKeys[code] { onAction?(.key(spec), true) }
        }
        for code in heldJoyCodes.subtracting(want) {
            if let spec = joyKeys[code] { onAction?(.key(spec), false) }
        }
        if want != heldJoyCodes {
            let names = want.map { String($0.dropFirst(3)) }.sorted().joined(separator: " ")
            flash(want.isEmpty ? "Đi: dừng" : "Đi: \(names)")
        }
        heldJoyCodes = want
    }

    // MARK: Cảm ứng

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            let p = t.location(in: self)
            if editing {
                if let id = buttonID(at: p) {
                    roles[t] = .editButton(id)
                    startPoints[t] = p
                } else if joystickHit(p) {
                    roles[t] = .editJoystick
                    startPoints[t] = p
                }
                continue
            }
            if let id = buttonID(at: p), let m = model(id) {
                roles[t] = .button(id)
                flash("Nút: \(m.label)")
                buttonViews[id]?.setPressed(true)
                recomputeAim()
                onAction?(m.action, true)
            } else if joystickHit(p) {
                roles[t] = .joystick
                moveJoystick(to: p)
            } else {
                roles[t] = .look
                if feedback { lookDot.center = p; lookDot.isHidden = false; lookTotal = .zero }
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            guard let role = roles[t] else { continue }
            let p = t.location(in: self)
            let prev = t.previousLocation(in: self)
            switch role {
            case .look:
                onLook?(p.x - prev.x, p.y - prev.y)
                if feedback {
                    lookDot.center = p
                    lookTotal.x += p.x - prev.x
                    lookTotal.y += p.y - prev.y
                    flash(String(format: "Vuốt: x %+.0f  y %+.0f", lookTotal.x, lookTotal.y))
                }
            case .joystick:
                moveJoystick(to: p)
            case .button:
                break
            case .editButton(let id):
                if let start = startPoints[t], hypot(p.x - start.x, p.y - start.y) > 8 { dragged.insert(t) }
                guard dragged.contains(t), bounds.width > 0, bounds.height > 0 else { break }
                if let i = PadStore.shared.settings.buttons.firstIndex(where: { $0.id == id }) {
                    var b = PadStore.shared.settings.buttons[i]
                    b.x = min(max(b.x + (p.x - prev.x) / bounds.width, 0.03), 0.97)
                    b.y = min(max(b.y + (p.y - prev.y) / bounds.height, 0.05), 0.95)
                    PadStore.shared.settings.buttons[i] = b
                    setNeedsLayout()
                }
            case .editJoystick:
                if let start = startPoints[t], hypot(p.x - start.x, p.y - start.y) > 8 { dragged.insert(t) }
                guard dragged.contains(t), bounds.width > 0, bounds.height > 0 else { break }
                var s = PadStore.shared.settings
                s.joyX = min(max(s.joyX + (p.x - prev.x) / bounds.width, 0.05), 0.95)
                s.joyY = min(max(s.joyY + (p.y - prev.y) / bounds.height, 0.08), 0.95)
                PadStore.shared.settings = s
                setNeedsLayout()
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish(touches, cancelled: false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish(touches, cancelled: true)
    }

    private func finish(_ touches: Set<UITouch>, cancelled: Bool) {
        for t in touches {
            guard let role = roles.removeValue(forKey: t) else { continue }
            let wasDragged = dragged.contains(t)
            dragged.remove(t)
            startPoints[t] = nil
            switch role {
            case .look:
                lookDot.isHidden = true
            case .joystick:
                joystick.setOffset(.zero)
                onJoystick?(0, 0)
                updateJoystickKeys()
            case .button(let id):
                buttonViews[id]?.setPressed(false)
                if let m = model(id) { onAction?(m.action, false) }
                recomputeAim()
            case .editButton(let id):
                PadStore.shared.save()
                if !wasDragged, !cancelled, let view = buttonViews[id] { onEditButton?(id, view) }
            case .editJoystick:
                PadStore.shared.save()
                if !wasDragged, !cancelled { onEditJoystick?(joystick) }
            }
        }
    }
}
