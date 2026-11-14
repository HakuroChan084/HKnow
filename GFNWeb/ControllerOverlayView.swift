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

// MARK: - Vùng vuốt xoay camera (chỉ hiện khi chỉnh sửa)

final class LookPadView: UIView {
    private let label = UILabel()
    private let border = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = UIColor.systemYellow.withAlphaComponent(0.08)
        border.fillColor = nil
        border.strokeColor = UIColor.systemYellow.cgColor
        border.lineWidth = 2
        border.lineDashPattern = [8, 6]
        layer.addSublayer(border)
        label.text = "Vùng xoay camera"
        label.textColor = UIColor.white.withAlphaComponent(0.55)
        label.font = .boldSystemFont(ofSize: 16)
        label.textAlignment = .center
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = 14
        border.frame = bounds
        border.path = UIBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), cornerRadius: 14).cgPath
        label.frame = bounds
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
    var onEditLook: ((UIView) -> Void)?
    /// Chế độ "Chạm = chuột": kéo ngón tay = di chuyển con trỏ trong game, chạm nhanh = click trái
    var onPointerMove: ((CGFloat, CGFloat) -> Void)?
    var onPointerClick: (() -> Void)?

    /// true = vùng trống ngoài nút / joystick / vùng xoay camera hoạt động như touchpad chuột
    var touchpadActive = false {
        didSet {
            guard oldValue != touchpadActive else { return }
            reset(notify: true)
        }
    }
    /// Nhấn giữ vào chỗ trống trong chế độ chỉnh sửa: điểm nhấn (toạ độ trong overlay)
    var onLongPressEmpty: ((CGPoint) -> Void)?

    /// Đang giữ nút Ngắm (LT / chuột phải) -> dùng cho gyro "chỉ khi ngắm"
    private(set) var aimHeld = false

    /// true = HUD đang ẩn: chỉ còn các nút "Ẩn/Hiện HUD" nhận chạm, mọi chạm khác đi xuyên xuống trang web
    var hudHidden = false {
        didSet {
            guard oldValue != hudHidden else { return }
            reset(notify: true)
            applyHudVisibility()
        }
    }

    var editing = false {
        didSet {
            guard oldValue != editing else { return }
            if editing { hudHidden = false }
            reset(notify: true)
            buttonViews.values.forEach { $0.editingStyle = editing }
            joystick.editingStyle = editing
            // Khi chơi: vùng xoay camera trong suốt 100% (ẩn hẳn), vùng cảm ứng vẫn hoạt động
            lookPad.isHidden = !editing
            hint.isHidden = !editing
        }
    }

    private enum Role {
        case look
        case joystick
        case button(UUID)
        case editButton(UUID)
        case editJoystick
        case editLook
        case pointer
    }

    private var buttonViews: [UUID: PadButtonView] = [:]
    private let joystick = JoystickView()
    private let lookPad = LookPadView()
    private let hint = UILabel()
    private lazy var longPress: UILongPressGestureRecognizer = {
        let g = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        g.minimumPressDuration = 0.5
        g.allowableMovement = 12
        g.cancelsTouchesInView = false
        g.delegate = self
        return g
    }()

    private var roles: [UITouch: Role] = [:]
    private var startPoints: [UITouch: CGPoint] = [:]
    private var dragged: Set<UITouch> = []
    private var startTimes: [UITouch: TimeInterval] = [:]
    private var heldJoyCodes: Set<String> = []

    private let joyKeys: [String: KeySpec] = [
        "KeyW": .w, "KeyA": .a, "KeyS": .s, "KeyD": .d,
    ]

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = true
        lookPad.isHidden = true
        addSubview(lookPad)
        addSubview(joystick)

        hint.text = "Chỉnh sửa: kéo để di chuyển • chạm nút / khung vàng để sửa • nhấn giữ chỗ trống để thêm nút"
        hint.textColor = .systemYellow
        hint.font = .boldSystemFont(ofSize: 14)
        hint.textAlignment = .center
        hint.isHidden = true
        hint.isUserInteractionEnabled = false
        addSubview(hint)

        addGestureRecognizer(longPress)
    }

    // MARK: Nhận cảm ứng

    /// Chưa bật bộ điều khiển (overlay ẩn): trả nil => MỌI cú chạm đi thẳng xuống WKWebView.
    /// Đang chơi: CHỈ nhận chạm ở nút tròn, joystick và vùng xoay camera. Mọi chỗ trống còn lại
    /// trả nil => chạm xuyên thẳng xuống trang web (bấm menu, chọn súng, Settings của game).
    /// Vùng xoay camera nuốt chạm nên vuốt / tap trong đó không bao giờ thành click chuột.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, isUserInteractionEnabled else { return nil }
        if editing { return super.hitTest(point, with: event) }
        // HUD đang ẩn: chỉ nút "Ẩn/Hiện HUD" còn nhận chạm
        if hudHidden { return buttonID(at: point) != nil ? self : nil }
        if touchpadActive { return self }
        if buttonID(at: point) != nil || joystickHit(point) || lookRect.contains(point) { return self }
        return nil
    }

    /// Vùng xoay camera (toạ độ trong overlay)
    private var lookRect: CGRect {
        let s = PadStore.shared.settings
        let w = s.lookWidth * bounds.width, h = s.lookHeight * bounds.height
        return CGRect(x: s.lookX * bounds.width - w / 2, y: s.lookY * bounds.height - h / 2, width: w, height: h)
    }

    // MARK: Nhấn giữ để thêm nút (chế độ chỉnh sửa)

    @objc private func handleLongPress(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began, editing else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onLongPressEmpty?(g.location(in: self))
    }

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
        applyHudVisibility()
        bringSubviewToFront(hint)
        setNeedsLayout()
    }

    /// Khi HUD ẩn: chỉ giữ lại các nút "Ẩn/Hiện HUD", ẩn joystick và mọi nút khác
    private func applyHudVisibility() {
        for b in PadStore.shared.settings.buttons {
            buttonViews[b.id]?.isHidden = hudHidden && b.action != .toggleHUD
        }
        joystick.isHidden = hudHidden
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let s = PadStore.shared.settings
        for b in s.buttons {
            guard let view = buttonViews[b.id] else { continue }
            view.bounds = CGRect(x: 0, y: 0, width: b.size, height: b.size)
            view.center = CGPoint(x: b.x * bounds.width, y: b.y * bounds.height)
        }
        lookPad.frame = lookRect
        joystick.bounds = CGRect(x: 0, y: 0, width: s.joySize, height: s.joySize)
        joystick.center = CGPoint(x: s.joyX * bounds.width, y: s.joyY * bounds.height)
        hint.frame = CGRect(x: 0, y: safeAreaInsets.top + 56, width: bounds.width, height: 24)
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
        startTimes.removeAll()
        dragged.removeAll()
        aimHeld = false
        buttonViews.values.forEach { $0.setPressed(false) }
        joystick.setOffset(.zero)
        if notify { onJoystick?(0, 0) }
    }

    // MARK: Tìm phần tử dưới ngón tay

    private func model(_ id: UUID) -> PadButton? {
        PadStore.shared.settings.buttons.first { $0.id == id }
    }

    private func buttonID(at p: CGPoint) -> UUID? {
        for b in PadStore.shared.settings.buttons.reversed() {
            guard let view = buttonViews[b.id], !view.isHidden else { continue }
            if hypot(p.x - view.center.x, p.y - view.center.y) <= b.size / 2 { return b.id }
        }
        return nil
    }

    private func joystickHit(_ p: CGPoint) -> Bool {
        !joystick.isHidden && hypot(p.x - joystick.center.x, p.y - joystick.center.y) <= joystick.radius
    }

    private func recomputeAim() {
        var held = false
        for (_, role) in roles {
            if case .button(let id) = role, let m = model(id), m.action.isAim { held = true }
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
        heldJoyCodes = want
    }

    // MARK: Cảm ứng

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            // Chuột / trackpad không điều khiển nút hay xoay camera
            if !editing, t.type == .indirectPointer { continue }
            let p = t.location(in: self)
            if editing {
                if let id = buttonID(at: p) {
                    roles[t] = .editButton(id)
                    startPoints[t] = p
                } else if joystickHit(p) {
                    roles[t] = .editJoystick
                    startPoints[t] = p
                } else if lookRect.contains(p) {
                    roles[t] = .editLook
                    startPoints[t] = p
                }
                continue
            }
            if let id = buttonID(at: p), let m = model(id) {
                roles[t] = .button(id)
                buttonViews[id]?.setPressed(true)
                recomputeAim()
                onAction?(m.action, true)
            } else if joystickHit(p) {
                roles[t] = .joystick
                moveJoystick(to: p)
            } else if !hudHidden, lookRect.contains(p) {
                // Trong vùng xoay camera: CHỈ để vuốt, chạm / giữ không bao giờ thành click chuột
                roles[t] = .look
            } else if touchpadActive, !hudHidden {
                roles[t] = .pointer
                startPoints[t] = p
                startTimes[t] = t.timestamp
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
            case .pointer:
                if let start = startPoints[t], hypot(p.x - start.x, p.y - start.y) > 10 { dragged.insert(t) }
                onPointerMove?(p.x - prev.x, p.y - prev.y)
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
            case .editLook:
                if let start = startPoints[t], hypot(p.x - start.x, p.y - start.y) > 8 { dragged.insert(t) }
                guard dragged.contains(t), bounds.width > 0, bounds.height > 0 else { break }
                var s = PadStore.shared.settings
                s.lookX += (p.x - prev.x) / bounds.width
                s.lookY += (p.y - prev.y) / bounds.height
                s.clampLookPad()
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
            let began = startTimes.removeValue(forKey: t)
            switch role {
            case .look:
                break
            case .pointer:
                // Chạm nhanh, gần như không di chuyển = click trái
                if !cancelled, !wasDragged, let b = began, t.timestamp - b < 0.3 { onPointerClick?() }
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
            case .editLook:
                PadStore.shared.save()
                if !wasDragged, !cancelled { onEditLook?(lookPad) }
            }
        }
    }
}

// MARK: - Nhấn giữ chỉ nhận ở chỗ trống khi đang chỉnh sửa

extension ControllerOverlayView: UIGestureRecognizerDelegate {
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === longPress else { return true }
        let p = gestureRecognizer.location(in: self)
        return editing && buttonID(at: p) == nil && !joystickHit(p) && !lookRect.contains(p)
    }
}
