import UIKit

// MARK: - Màu chủ đạo (xanh NVIDIA)

enum Neon {
    static let accent = UIColor(red: 0.463, green: 0.725, blue: 0.0, alpha: 1)
    static let panel = UIColor(red: 0.055, green: 0.065, blue: 0.075, alpha: 0.97)
    static let row = UIColor(white: 1, alpha: 0.07)
    static let sub = UIColor(white: 1, alpha: 0.55)
    static let warn = UIColor(red: 1.0, green: 0.45, blue: 0.25, alpha: 1)
}

// MARK: - Sự kiện con trỏ (chế độ Chuột / Launcher)

enum PointerEvent {
    case move(CGPoint, CGPoint)         // vị trí con trỏ, độ dời của con trỏ trong lần di chuyển này (.zero = vừa chạm xuống)
    case down(CGPoint, Int)             // vị trí, nút (0 trái, 2 phải)
    case up(CGPoint, Int)
    case click(CGPoint, Int, Int)       // vị trí, nút, số lần bấm liên tiếp (1 hoặc 2)
    case wheel(CGPoint, CGFloat)        // vị trí, độ dời dọc của ngón tay
}

// MARK: - Nút tròn nhỏ + / − / ⚙︎ hiện cạnh nút đang chọn (chế độ chỉnh sửa)

final class ChipButton: UIButton {
    /// Chạm 1 lần (hoặc lần đầu khi bắt đầu giữ)
    var onTap: (() -> Void)?
    /// Lặp liên tục khi giữ lâu hơn 0.3 giây (chỉ với nút lặp)
    var onTick: (() -> Void)?
    /// Thả tay (nút lặp) -> lưu cài đặt
    var onEnd: (() -> Void)?

    private let repeating: Bool
    private var delayItem: DispatchWorkItem?
    private var timer: Timer?

    init(symbol: String, repeating: Bool) {
        self.repeating = repeating
        super.init(frame: CGRect(x: 0, y: 0, width: 34, height: 34))
        let cfg = UIImage.SymbolConfiguration(pointSize: 15, weight: .heavy)
        setImage(UIImage(systemName: symbol, withConfiguration: cfg), for: .normal)
        tintColor = .black
        backgroundColor = Neon.accent.withAlphaComponent(0.96)
        layer.cornerRadius = 17
        layer.borderWidth = 1.5
        layer.borderColor = UIColor.white.withAlphaComponent(0.85).cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.4
        layer.shadowRadius = 4
        layer.shadowOffset = CGSize(width: 0, height: 2)
        addTarget(self, action: #selector(pressed), for: .touchDown)
        addTarget(self, action: #selector(released), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { stopRepeat() }

    @objc private func pressed() {
        guard repeating else { return }
        onTap?()
        stopRepeat()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let t = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in self?.onTick?() }
            RunLoop.main.add(t, forMode: .common)
            self.timer = t
        }
        delayItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    @objc private func released() {
        guard repeating else { return }
        stopRepeat()
        onEnd?()
    }

    @objc private func tapped() {
        if !repeating { onTap?() }
    }

    private func stopRepeat() {
        delayItem?.cancel()
        delayItem = nil
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - Nút tròn

final class PadButtonView: UIView {
    private let label = UILabel()
    private var pressed = false

    var editingStyle = false { didSet { updateStyle() } }
    var selectedStyle = false { didSet { updateStyle() } }

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
        let border: UIColor
        if selectedStyle { border = Neon.accent }
        else if editingStyle { border = .systemYellow }
        else { border = UIColor.white.withAlphaComponent(0.75) }
        layer.borderColor = border.cgColor
        layer.borderWidth = selectedStyle ? 3.5 : 2
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
    var selectedStyle = false { didSet { updateStyle() } }

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
        let border: UIColor
        if selectedStyle { border = Neon.accent }
        else if editingStyle { border = .systemYellow }
        else { border = UIColor.white.withAlphaComponent(0.6) }
        layer.borderColor = border.cgColor
        layer.borderWidth = selectedStyle ? 3.5 : 2
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
    /// Ngón tay đang vuốt xoay camera vừa nhấc lên (để app phanh cần gạt, không trượt quán tính)
    var onLookEnd: (() -> Void)?
    var onAction: ((PadAction, Bool) -> Void)?
    /// Độ lệch joystick đi đã chuẩn hóa: x, y trong [-1, 1], y dương = kéo xuống (dùng cho cần gạt trái của tay cầm ảo)
    var onJoystick: ((CGFloat, CGFloat) -> Void)?
    var onEditButton: ((UUID, UIView) -> Void)?
    var onEditJoystick: ((UIView) -> Void)?
    /// Nhấn giữ vào chỗ trống trong chế độ chỉnh sửa: điểm nhấn (toạ độ trong overlay)
    var onLongPressEmpty: ((CGPoint) -> Void)?
    /// Chế độ Chuột / Launcher: sự kiện con trỏ ảo (toạ độ trong overlay, trùng toạ độ WebView)
    var onPointer: ((PointerEvent) -> Void)?

    /// Chế độ Chuột / Launcher có hai cách điều khiển con trỏ:
    ///  - false (mặc định): con trỏ BÁM NGÓN TAY. Chạm xuống đâu con trỏ nhảy tới đó, tap = bấm đúng chỗ ngón tay vừa chạm.
    ///    Dùng khi trang đang nhận toạ độ tuyệt đối (GFN chưa khóa chuột).
    ///  - true: TRACKPAD. GFN đang khóa chuột nên chỉ nhận độ dời tương đối: kéo ngón tay = cộng dồn dx, dy (có gia tốc)
    ///    như trackpad laptop, nhấc ngón ra con trỏ vẫn đứng yên, tap = bấm tại chỗ con trỏ đang đứng.
    /// WebViewController tự đặt theo trạng thái khóa chuột của trang.
    var relativeCursor = false

    /// Hệ số nhân độ dời ở chế độ trackpad: vuốt chậm = gần 1:1 để nhắm chính xác nút nhỏ, vuốt nhanh = tăng dần tới trần
    private let trackpadBaseGain: CGFloat = 1.1
    private let trackpadAccel: CGFloat = 1800       // mỗi 1800 pt/giây hệ số tăng thêm 1.0
    private let trackpadMaxGain: CGFloat = 3.0

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

    /// .hud = Chiến đấu (nút ảo + vuốt xoay camera) | .mouse = Chuột / Launcher (ẩn nút, chạm = con trỏ chuột)
    var mode: ControlMode = .hud {
        didSet {
            guard oldValue != mode else { return }
            reset(notify: true)
            selection = nil
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
            hint.isHidden = !editing
            if !editing { selection = nil }
            updateSelectionUI()
        }
    }

    private enum Role {
        case look
        case joystick
        case button(UUID)
        case editButton(UUID)
        case editJoystick
        case mouse
    }

    /// Phần tử đang được chọn trong chế độ chỉnh sửa (hiện nút + / − / ⚙︎ cạnh nó)
    private enum Selection: Equatable {
        case button(UUID)
        case joystick
    }

    private struct MouseState {
        var cursor = CGPoint.zero               // vị trí con trỏ ảo (nhớ lại giữa các lần chạm)
        var startTime: TimeInterval = 0
        var startPoint = CGPoint.zero
        var lastMoveTime: TimeInterval = 0
        var primary: ObjectIdentifier?          // ngón đầu tiên của cử chỉ hiện tại
        var moved = false
        var downSent = false
        var twoFinger = false
        var twoStart: TimeInterval = 0
        var twoTravel: CGFloat = 0
        var lastTapTime: TimeInterval = 0
        var lastTapPoint = CGPoint.zero
    }

    private var buttonViews: [UUID: PadButtonView] = [:]
    private let joystick = JoystickView()
    private let hint = UILabel()
    private let plusChip = ChipButton(symbol: "plus", repeating: true)
    private let minusChip = ChipButton(symbol: "minus", repeating: true)
    private let gearChip = ChipButton(symbol: "gearshape.fill", repeating: false)
    private var selection: Selection? {
        didSet { updateSelectionUI() }
    }
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
    private var heldJoyCodes: Set<String> = []

    private var ms = MouseState()
    private var holdItem: DispatchWorkItem?

    private let joyKeys: [String: KeySpec] = [
        "KeyW": .w, "KeyA": .a, "KeyS": .s, "KeyD": .d,
    ]

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = true
        addSubview(joystick)

        hint.text = "Chỉnh sửa: kéo để di chuyển • chạm nút để chọn (+ / −) • chạm lần nữa hoặc ⚙︎ để mở cài đặt • nhấn giữ chỗ trống để thêm nút"
        hint.textColor = .systemYellow
        hint.font = .boldSystemFont(ofSize: 13)
        hint.textAlignment = .center
        hint.adjustsFontSizeToFitWidth = true
        hint.minimumScaleFactor = 0.6
        hint.isHidden = true
        hint.isUserInteractionEnabled = false
        addSubview(hint)

        // Nút + / − / ⚙︎ cạnh phần tử đang chọn
        for chip in [plusChip, minusChip, gearChip] {
            chip.isHidden = true
            addSubview(chip)
        }
        plusChip.onTap = { [weak self] in self?.scaleSelected(1.08) }
        plusChip.onTick = { [weak self] in self?.scaleSelected(1.03) }
        plusChip.onEnd = { PadStore.shared.save() }
        minusChip.onTap = { [weak self] in self?.scaleSelected(1 / 1.08) }
        minusChip.onTick = { [weak self] in self?.scaleSelected(1 / 1.03) }
        minusChip.onEnd = { PadStore.shared.save() }
        gearChip.onTap = { [weak self] in self?.openSelectedSettings() }

        addGestureRecognizer(longPress)
    }

    // MARK: Nhận cảm ứng

    /// Chưa bật bộ điều khiển (overlay ẩn): trả nil => MỌI cú chạm đi thẳng xuống WKWebView.
    /// Đã bật: overlay nuốt toàn bộ cảm ứng => không có chạm / tap / giữ nào lọt xuống trang web
    /// => không thể "cướp cò" bắn nhầm. Nút và joystick chỉ nhận trong hình tròn của chúng,
    /// vùng trống còn lại chỉ dùng để vuốt xoay camera.
    /// Chế độ Chuột / Launcher: overlay nhận mọi chạm bằng ngón tay (để vẽ con trỏ ảo), chuột thật đi xuyên xuống.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, isUserInteractionEnabled else { return nil }
        if mode == .mouse {
            if let t = event?.allTouches?.first, t.type == .indirectPointer { return nil }
            return self
        }
        // HUD đang ẩn: chỉ nút "Ẩn/Hiện HUD" còn nhận chạm, phần còn lại đi thẳng xuống trang web
        if hudHidden, !editing { return buttonID(at: point) != nil ? self : nil }
        return super.hitTest(point, with: event)
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
                insertSubview(view, belowSubview: hint)
                buttonViews[b.id] = view
            }
        }
        if case .button(let id)? = selection, !ids.contains(id) { selection = nil }
        applyHudVisibility()
        bringSubviewToFront(hint)
        for chip in [plusChip, minusChip, gearChip] { bringSubviewToFront(chip) }
        updateSelectionUI()
        setNeedsLayout()
    }

    /// Khi HUD ẩn: chỉ giữ lại các nút "Ẩn/Hiện HUD", ẩn joystick và mọi nút khác.
    /// Chế độ Chuột / Launcher: ẩn tất cả.
    private func applyHudVisibility() {
        let mouse = (mode == .mouse)
        for b in PadStore.shared.settings.buttons {
            buttonViews[b.id]?.isHidden = mouse || (hudHidden && b.action != .toggleHUD)
        }
        joystick.isHidden = mouse || hudHidden
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
        hint.frame = CGRect(x: 12, y: safeAreaInsets.top + 42, width: max(bounds.width - 24, 0), height: 22)
        layoutChips()
    }

    // MARK: Chọn phần tử + nút + / − / ⚙︎

    private func updateSelectionUI() {
        for (id, view) in buttonViews {
            view.selectedStyle = editing && selection == .button(id)
        }
        joystick.selectedStyle = editing && selection == .joystick
        let show = editing && selection != nil
        for chip in [plusChip, minusChip, gearChip] { chip.isHidden = !show }
        setNeedsLayout()
    }

    private func layoutChips() {
        guard editing, let sel = selection else { return }
        let center: CGPoint
        let radius: CGFloat
        switch sel {
        case .button(let id):
            guard let view = buttonViews[id], let m = model(id) else { return }
            center = view.center
            radius = m.size / 2
        case .joystick:
            center = joystick.center
            radius = joystick.radius
        }
        let chipR: CGFloat = 17
        let gap: CGFloat = 40
        var x = center.x + radius + 12 + chipR
        if x + chipR > bounds.width - 6 { x = center.x - radius - 12 - chipR }
        x = min(max(x, chipR + 6), max(bounds.width - chipR - 6, chipR + 6))
        let minY = gap + chipR + 6
        let maxY = max(bounds.height - gap - chipR - 6, minY)
        let midY = min(max(center.y, minY), maxY)
        plusChip.center = CGPoint(x: x, y: midY - gap)
        minusChip.center = CGPoint(x: x, y: midY)
        gearChip.center = CGPoint(x: x, y: midY + gap)
    }

    /// Phóng to / thu nhỏ phần tử đang chọn
    private func scaleSelected(_ factor: CGFloat) {
        guard let sel = selection else { return }
        switch sel {
        case .button(let id):
            guard let i = PadStore.shared.settings.buttons.firstIndex(where: { $0.id == id }) else { return }
            let size = PadStore.shared.settings.buttons[i].size
            PadStore.shared.settings.buttons[i].size = min(max(size * factor, 36), 220)
        case .joystick:
            let size = PadStore.shared.settings.joySize
            PadStore.shared.settings.joySize = min(max(size * factor, 90), 300)
        }
        setNeedsLayout()
    }

    private func openSelectedSettings() {
        guard let sel = selection else { return }
        switch sel {
        case .button(let id):
            if let view = buttonViews[id] { onEditButton?(id, view) }
        case .joystick:
            onEditJoystick?(joystick)
        }
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
            if ms.downSent { onPointer?(.up(ms.cursor, 0)) }
        }
        cancelHold()
        let cursor = ms.cursor
        ms = MouseState()
        ms.cursor = cursor
        heldJoyCodes.removeAll()
        roles.removeAll()
        startPoints.removeAll()
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

    // MARK: Chuột / Launcher (con trỏ ảo)

    private var mouseTouchCount: Int {
        roles.values.filter { if case .mouse = $0 { return true } else { return false } }.count
    }

    private func scheduleHold() {
        cancelHold()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.mode == .mouse, !self.ms.moved, !self.ms.twoFinger,
                  !self.ms.downSent, self.mouseTouchCount == 1 else { return }
            self.ms.downSent = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            self.onPointer?(.down(self.ms.cursor, 0))
        }
        holdItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: item)
    }

    private func cancelHold() {
        holdItem?.cancel()
        holdItem = nil
    }

    private func clampToBounds(_ p: CGPoint) -> CGPoint {
        guard bounds.width > 0, bounds.height > 0 else { return p }
        return CGPoint(x: min(max(p.x, 0), bounds.width), y: min(max(p.y, 0), bounds.height))
    }

    /// Đặt vị trí con trỏ ảo (WebViewController gọi khi vào chế độ Chuột để con trỏ khởi đầu ở giữa màn hình)
    func setCursor(_ p: CGPoint) {
        ms.cursor = clampToBounds(p)
    }

    private func mouseBegan(_ t: UITouch) {
        let p = t.location(in: self)
        roles[t] = .mouse
        if mouseTouchCount == 1 {
            ms.primary = ObjectIdentifier(t)
            ms.startTime = t.timestamp
            ms.startPoint = p
            ms.lastMoveTime = t.timestamp
            ms.moved = false
            ms.downSent = false
            ms.twoFinger = false
            if !relativeCursor {
                // Bám ngón tay: con trỏ nhảy tới chỗ chạm và báo ngay để trang rê chuột tới đó trước khi bấm
                ms.cursor = clampToBounds(p)
                onPointer?(.move(ms.cursor, .zero))
            }
            // Trackpad: chạm xuống chưa làm con trỏ nhúc nhích, chỉ kéo / tap mới có tác dụng
            scheduleHold()
        } else {
            // Ngón thứ hai: chuột phải (chạm nhanh) hoặc cuộn (kéo)
            cancelHold()
            if ms.downSent {
                onPointer?(.up(ms.cursor, 0))
                ms.downSent = false
            }
            ms.twoFinger = true
            ms.twoStart = t.timestamp
            ms.twoTravel = 0
        }
    }

    private func mouseMoved(_ t: UITouch) {
        let p = t.location(in: self)
        let prev = t.previousLocation(in: self)
        let d = CGPoint(x: p.x - prev.x, y: p.y - prev.y)

        if ms.twoFinger {
            // Hai ngón: chỉ tính chuyển động của ngón thứ hai để cuộn (ngón đầu không tính đôi, cũng không rê con trỏ)
            guard ms.primary != ObjectIdentifier(t) else { return }
            ms.twoTravel += abs(d.x) + abs(d.y)
            if ms.twoTravel > 8 { onPointer?(.wheel(ms.cursor, d.y)) }
            return
        }

        var delta = d
        if relativeCursor {
            // Trackpad: cộng dồn độ dời ngón tay (có gia tốc theo tốc độ vuốt)
            let dt = max(t.timestamp - ms.lastMoveTime, 1.0 / 240.0)
            let speed = hypot(d.x, d.y) / CGFloat(dt)
            let gain = min(trackpadBaseGain + speed / trackpadAccel, trackpadMaxGain)
            delta = CGPoint(x: d.x * gain, y: d.y * gain)
            ms.cursor = clampToBounds(CGPoint(x: ms.cursor.x + delta.x, y: ms.cursor.y + delta.y))
        } else {
            // Bám ngón tay: con trỏ nằm đúng chỗ ngón tay
            ms.cursor = clampToBounds(p)
        }
        ms.lastMoveTime = t.timestamp

        if !ms.downSent, hypot(p.x - ms.startPoint.x, p.y - ms.startPoint.y) > 10 {
            ms.moved = true
            cancelHold()
        }
        onPointer?(.move(ms.cursor, delta))
    }

    private func mouseEnded(_ t: UITouch, cancelled: Bool) {
        cancelHold()
        if ms.twoFinger {
            if mouseTouchCount == 0 {
                if !cancelled, ms.twoTravel < 12, t.timestamp - ms.twoStart < 0.4 {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onPointer?(.click(ms.cursor, 2, 1))
                }
                ms.twoFinger = false
            }
            return
        }
        if ms.downSent {
            ms.downSent = false
            onPointer?(.up(ms.cursor, 0))
        } else if !cancelled, !ms.moved, t.timestamp - ms.startTime < 0.4 {
            let now = t.timestamp
            let isDouble = now - ms.lastTapTime < 0.35
                && hypot(ms.cursor.x - ms.lastTapPoint.x, ms.cursor.y - ms.lastTapPoint.y) < 30
            ms.lastTapTime = isDouble ? 0 : now
            ms.lastTapPoint = ms.cursor
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onPointer?(.click(ms.cursor, 0, isDouble ? 2 : 1))
        }
    }

    // MARK: Cảm ứng

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            // Chuột / trackpad không điều khiển nút hay xoay camera
            if !editing, t.type == .indirectPointer { continue }
            if mode == .mouse {
                mouseBegan(t)
                continue
            }
            let p = t.location(in: self)
            if editing {
                if let id = buttonID(at: p) {
                    roles[t] = .editButton(id)
                    startPoints[t] = p
                } else if joystickHit(p) {
                    roles[t] = .editJoystick
                    startPoints[t] = p
                } else {
                    selection = nil     // chạm chỗ trống: bỏ chọn
                }
                continue
            }
            if let id = buttonID(at: p), let m = model(id) {
                roles[t] = .button(id)
                startPoints[t] = p
                buttonViews[id]?.setPressed(true)
                recomputeAim()
                onAction?(m.action, true)
            } else if joystickHit(p) {
                roles[t] = .joystick
                moveJoystick(to: p)
            } else if !hudHidden {
                // Vùng trống: CHỈ để vuốt xoay camera, chạm / giữ không bao giờ thành click chuột
                roles[t] = .look
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
            case .joystick:
                moveJoystick(to: p)
            case .button(let id):
                // Giữ nút + kéo ngón tay: vừa giữ lệnh (bắn / ngắm...) vừa xoay camera (ghìm tâm)
                guard !editing, let m = model(id), m.allowDragLook else { break }
                if dragged.contains(t) {
                    onLook?(p.x - prev.x, p.y - prev.y)
                } else if let start = startPoints[t], hypot(p.x - start.x, p.y - start.y) > 3 {
                    dragged.insert(t)       // bỏ qua rung nhẹ lúc nhấn
                }
            case .mouse:
                mouseMoved(t)
            case .editButton(let id):
                if let start = startPoints[t], hypot(p.x - start.x, p.y - start.y) > 8 { dragged.insert(t) }
                guard dragged.contains(t), bounds.width > 0, bounds.height > 0 else { break }
                if selection != .button(id) { selection = .button(id) }
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
                if selection != .joystick { selection = .joystick }
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
                onLookEnd?()
            case .joystick:
                joystick.setOffset(.zero)
                onJoystick?(0, 0)
                updateJoystickKeys()
            case .button(let id):
                buttonViews[id]?.setPressed(false)
                if let m = model(id) { onAction?(m.action, false) }
                recomputeAim()
                if wasDragged { onLookEnd?() }
            case .mouse:
                mouseEnded(t, cancelled: cancelled)
            case .editButton(let id):
                PadStore.shared.save()
                if !wasDragged, !cancelled {
                    if selection == .button(id) {
                        if let view = buttonViews[id] { onEditButton?(id, view) }   // chạm lần 2: mở cài đặt riêng của nút
                    } else {
                        selection = .button(id)                                     // chạm lần 1: chọn -> hiện + / −
                    }
                }
            case .editJoystick:
                PadStore.shared.save()
                if !wasDragged, !cancelled {
                    if selection == .joystick {
                        onEditJoystick?(joystick)
                    } else {
                        selection = .joystick
                    }
                }
            }
        }
    }
}

// MARK: - Nhấn giữ chỉ nhận ở chỗ trống khi đang chỉnh sửa

extension ControllerOverlayView: UIGestureRecognizerDelegate {
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === longPress else { return true }
        let p = gestureRecognizer.location(in: self)
        guard editing, buttonID(at: p) == nil, !joystickHit(p) else { return false }
        for chip in [plusChip, minusChip, gearChip] where !chip.isHidden {
            if chip.frame.insetBy(dx: -10, dy: -10).contains(p) { return false }
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !(touch.view is UIControl)
    }
}
