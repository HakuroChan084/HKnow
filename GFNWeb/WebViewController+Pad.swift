import UIKit
import WebKit

// Thanh Setting + công tắc nhanh ở mép trên màn hình, bảng cài đặt gaming, các hộp thoại chỉnh sửa nút
extension WebViewController {

    // MARK: - Thanh trên cùng (Setting + công tắc Chiến đấu / Chuột)

    func setupGearButton() {
        topBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topBar)
        NSLayoutConstraint.activate([
            topBar.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            topBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 3),
            topBar.heightAnchor.constraint(equalToConstant: 32),
        ])
        topBar.settingsButton.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)
        topBar.modeToggle.addTarget(self, action: #selector(modeToggleTapped), for: .touchUpInside)
        topBar.doneButton.addTarget(self, action: #selector(doneEditingTapped), for: .touchUpInside)
        topBar.scheduleDim()
        refreshMenu()
    }

    @objc private func settingsTapped() {
        topBar.wake()
        presentSettingsPanel()
    }

    @objc private func modeToggleTapped() {
        topBar.wake()
        setControlMode(controlMode == .hud ? .mouse : .hud)
    }

    @objc private func doneEditingTapped() {
        padEditing = false
        PadStore.shared.save()
    }

    func commitPad() {
        PadStore.shared.save()
        overlay.reload()
        applyPadState()
    }

    /// Cập nhật thanh trên cùng (và bảng cài đặt nếu đang mở) theo trạng thái hiện tại
    func refreshMenu() {
        guard isViewLoaded else { return }
        topBar.update(mode: controlMode, editing: padEditing)
        settingsPanel?.syncState()
    }

    // MARK: - Bảng cài đặt gaming

    func presentSettingsPanel() {
        if settingsPanel != nil {
            dismissSettingsPanel()
            return
        }
        let panel = GamingPanelView(host: self)
        panel.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(panel, belowSubview: topBar)
        NSLayoutConstraint.activate([
            panel.topAnchor.constraint(equalTo: view.topAnchor),
            panel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            panel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        view.layoutIfNeeded()
        settingsPanel = panel
        topBar.panelOpen = true
        panel.animateIn()
    }

    func dismissSettingsPanel() {
        guard let panel = settingsPanel else { return }
        settingsPanel = nil
        topBar.panelOpen = false
        panel.animateOut()
    }

    // MARK: - Thêm nút

    func addButtonFlow() {
        addButton(at: CGPoint(x: 0.5, y: 0.5), source: gearButton)
    }

    /// Nhấn giữ vào chỗ trống (chế độ chỉnh sửa): popup thêm nút ngay tại điểm vừa nhấn
    func presentAddButtonAt(_ point: CGPoint) {
        guard padEditing, overlay.bounds.width > 0, overlay.bounds.height > 0 else { return }
        let norm = CGPoint(
            x: min(max(point.x / overlay.bounds.width, 0.03), 0.97),
            y: min(max(point.y / overlay.bounds.height, 0.05), 0.95)
        )
        let sheet = UIAlertController(title: "Thêm nút tại đây", message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Chọn hành động / phím…", style: .default) { [weak self] _ in
            self?.addButton(at: norm, source: self?.overlay ?? UIView())
        })
        for action in [PadAction.mouse(0), .mouse(2), .key(.space), .toggleKeyboard, .toggleHUD] {
            sheet.addAction(UIAlertAction(title: action.title, style: .default) { [weak self] _ in
                self?.insertButton(action, at: norm)
            })
        }
        sheet.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = overlay
            pop.sourceRect = CGRect(x: point.x, y: point.y, width: 1, height: 1)
        }
        present(sheet, animated: true)
    }

    private func addButton(at norm: CGPoint, source: UIView) {
        presentActionChooser(title: "Chọn hành động cho nút mới", source: source) { [weak self] action in
            self?.insertButton(action, at: norm)
        }
    }

    private func insertButton(_ action: PadAction, at norm: CGPoint) {
        let button = PadButton(label: action.defaultLabel, action: action, x: norm.x, y: norm.y, size: 64)
        PadStore.shared.settings.buttons.append(button)
        PadStore.shared.save()
        overlay.reload()
        padEditing = true     // bật chế độ chỉnh sửa để kéo nút tới chỗ mong muốn
    }

    // MARK: - Hộp thoại chọn hành động

    /// Bảng chọn dạng lưới, chia nhóm: tay cầm / phím bổ trợ / phím điều khiển / F1–F12 / mũi tên / A–Z / số & dấu / hệ thống
    func presentActionChooser(title: String, source: UIView, completion: @escaping (PadAction) -> Void) {
        let picker = ActionPickerViewController(title: title, groups: PadAction.catalog)
        picker.onPick = completion
        picker.onCustomKey = { [weak self] in self?.askCustomKey(completion) }
        let nav = UINavigationController(rootViewController: picker)
        nav.modalPresentationStyle = .pageSheet
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(nav, animated: true)
    }

    private func askCustomKey(_ completion: @escaping (PadAction) -> Void) {
        let alert = UIAlertController(
            title: "Phím khác",
            message: "Gõ 1 phím: chữ cái, số, F1–F12, space, shift, ctrl, alt, tab, esc, up, down, left, right",
            preferredStyle: .alert
        )
        alert.addTextField { $0.autocapitalizationType = .none; $0.placeholder = "ví dụ: t" }
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self, weak alert] _ in
            let text = alert?.textFields?.first?.text ?? ""
            if let spec = KeySpec.parse(text) {
                completion(.key(spec))
            } else {
                let err = UIAlertController(title: "Không nhận ra phím này", message: nil, preferredStyle: .alert)
                err.addAction(UIAlertAction(title: "OK", style: .default))
                self?.present(err, animated: true)
            }
        })
        present(alert, animated: true)
    }

    // MARK: - Sửa nút

    private func mutateButton(_ id: UUID, _ change: (inout PadButton) -> Void) {
        guard let i = PadStore.shared.settings.buttons.firstIndex(where: { $0.id == id }) else { return }
        change(&PadStore.shared.settings.buttons[i])
        PadStore.shared.save()
        overlay.reload()
    }

    func presentButtonEditor(_ id: UUID, from source: UIView) {
        guard let b = PadStore.shared.settings.buttons.first(where: { $0.id == id }) else { return }
        let sheet = UIAlertController(
            title: "\(b.label) — \(b.action.title)",
            message: "Cỡ \(Int(b.size)) pt • dùng nút + / − cạnh nút để phóng to / thu nhỏ",
            preferredStyle: .actionSheet
        )

        // Giữ nút + kéo ngón tay = vừa giữ lệnh vừa xoay camera (ghìm tâm / xoay ngắm bằng ngón đang giữ nút)
        let dragTitle = b.allowDragLook
            ? "✓ Cho phép vuốt xoay camera khi giữ nút"
            : "Cho phép vuốt xoay camera khi giữ nút (đang tắt)"
        sheet.addAction(UIAlertAction(title: dragTitle, style: .default) { [weak self] _ in
            self?.mutateButton(id) { $0.allowDragLook.toggle() }
        })
        sheet.addAction(UIAlertAction(title: "Đổi hành động…", style: .default) { [weak self] _ in
            self?.presentActionChooser(title: "Hành động mới", source: source) { action in
                self?.mutateButton(id) { $0.action = action; $0.label = action.defaultLabel }
            }
        })
        sheet.addAction(UIAlertAction(title: "Đổi tên nhãn…", style: .default) { [weak self] _ in
            let alert = UIAlertController(title: "Tên nhãn", message: nil, preferredStyle: .alert)
            alert.addTextField { $0.text = b.label }
            alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak alert] _ in
                let text = alert?.textFields?.first?.text ?? ""
                self?.mutateButton(id) { $0.label = text }
            })
            self?.present(alert, animated: true)
        })
        sheet.addAction(UIAlertAction(title: "Nhân bản", style: .default) { [weak self] _ in
            guard let self, let src = PadStore.shared.settings.buttons.first(where: { $0.id == id }) else { return }
            var copy = src
            copy.id = UUID()
            copy.x = min(src.x + 0.07, 0.97)
            copy.y = min(src.y + 0.10, 0.95)
            PadStore.shared.settings.buttons.append(copy)
            PadStore.shared.save()
            self.overlay.reload()
        })
        sheet.addAction(UIAlertAction(title: "Xóa nút", style: .destructive) { [weak self] _ in
            PadStore.shared.settings.buttons.removeAll { $0.id == id }
            PadStore.shared.save()
            self?.overlay.reload()
        })
        sheet.addAction(UIAlertAction(title: "Xong", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = source
            pop.sourceRect = source.bounds
        }
        present(sheet, animated: true)
    }

    func presentJoystickEditor(from source: UIView) {
        let size = Int(PadStore.shared.settings.joySize)
        let sheet = UIAlertController(
            title: "Joystick đi (W A S D)",
            message: "Cỡ \(size) pt • dùng nút + / − cạnh joystick để phóng to / thu nhỏ",
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(title: "Đặt lại vị trí & cỡ mặc định", style: .default) { [weak self] _ in
            let d = PadSettings()
            PadStore.shared.settings.joyX = d.joyX
            PadStore.shared.settings.joyY = d.joyY
            PadStore.shared.settings.joySize = d.joySize
            self?.commitPad()
        })
        sheet.addAction(UIAlertAction(title: "Xong", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = source
            pop.sourceRect = source.bounds
        }
        present(sheet, animated: true)
    }
}

// MARK: - Ô nhập liệu ẩn: nhận ký tự từ bàn phím ảo iOS

final class KeyCatcherField: UITextField, UITextFieldDelegate {
    var onText: ((String) -> Void)?
    var onBackspace: (() -> Void)?
    var onReturn: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        delegate = self
    }

    override func deleteBackward() { onBackspace?() }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        if string == "\n" { onReturn?() } else if !string.isEmpty { onText?(string) }
        return false     // ô luôn rỗng: không giữ chữ lại
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        onReturn?()
        return false
    }
}

// MARK: - Bảng chọn hành động dạng lưới

final class ActionPickerViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegate {
    var onPick: ((PadAction) -> Void)?
    var onCustomKey: (() -> Void)?
    private let groups: [ActionGroup]
    private var collection: UICollectionView!

    init(title: String, groups: [ActionGroup]) {
        self.groups = groups
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Hủy", style: .plain, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Phím khác…", style: .plain, target: self, action: #selector(custom))

        let layout = UICollectionViewCompositionalLayout { _, _ in
            let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .absolute(78), heightDimension: .absolute(56)))
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(56)),
                subitems: [item]
            )
            group.interItemSpacing = .fixed(8)
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 8
            section.contentInsets = .init(top: 4, leading: 12, bottom: 16, trailing: 12)
            let header = NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(30)),
                elementKind: UICollectionView.elementKindSectionHeader, alignment: .top
            )
            section.boundarySupplementaryItems = [header]
            return section
        }
        collection = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collection.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collection.backgroundColor = .systemBackground
        collection.dataSource = self
        collection.delegate = self
        collection.register(ActionCell.self, forCellWithReuseIdentifier: "cell")
        collection.register(
            SectionHeader.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: "header"
        )
        view.addSubview(collection)
    }

    @objc private func cancel() { dismiss(animated: true) }

    @objc private func custom() {
        dismiss(animated: true) { [onCustomKey] in onCustomKey?() }
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int { groups.count }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        groups[section].items.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! ActionCell
        let item = groups[indexPath.section].items[indexPath.item]
        cell.configure(item.label, item.detail)
        return cell
    }

    func collectionView(
        _ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath
    ) -> UICollectionReusableView {
        let v = collectionView.dequeueReusableSupplementaryView(
            ofKind: kind, withReuseIdentifier: "header", for: indexPath
        ) as! SectionHeader
        v.label.text = groups[indexPath.section].title
        return v
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let action = groups[indexPath.section].items[indexPath.item].action
        dismiss(animated: true) { [onPick] in onPick?(action) }
    }
}

private final class ActionCell: UICollectionViewCell {
    private let title = UILabel()
    private let detail = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .secondarySystemBackground
        contentView.layer.cornerRadius = 10
        title.font = .boldSystemFont(ofSize: 15)
        title.textAlignment = .center
        title.adjustsFontSizeToFitWidth = true
        title.minimumScaleFactor = 0.6
        detail.font = .systemFont(ofSize: 10)
        detail.textColor = .secondaryLabel
        detail.textAlignment = .center
        detail.adjustsFontSizeToFitWidth = true
        detail.minimumScaleFactor = 0.6
        let stack = UIStackView(arrangedSubviews: [title, detail])
        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ label: String, _ sub: String?) {
        title.text = label
        detail.text = sub
        detail.isHidden = (sub ?? "").isEmpty
    }

    override var isHighlighted: Bool {
        didSet { contentView.backgroundColor = isHighlighted ? .tertiarySystemFill : .secondarySystemBackground }
    }
}

private final class SectionHeader: UICollectionReusableView {
    let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = .boldSystemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// MARK: - Công tắc nhanh Chiến đấu ⇄ Chuột

final class ModeToggleView: UIControl {
    private let thumb = UIView()
    private let hudIcon = UIImageView()
    private let mouseIcon = UIImageView()
    private(set) var mode: ControlMode = .hud

    override var intrinsicContentSize: CGSize { CGSize(width: 68, height: 26) }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.white.withAlphaComponent(0.12)
        layer.cornerRadius = 13
        thumb.backgroundColor = Neon.accent
        thumb.isUserInteractionEnabled = false
        addSubview(thumb)

        let cfg = UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)
        hudIcon.image = UIImage(systemName: "gamecontroller.fill", withConfiguration: cfg)
        mouseIcon.image = UIImage(systemName: "computermouse.fill", withConfiguration: cfg)
            ?? UIImage(systemName: "cursorarrow", withConfiguration: cfg)
        for icon in [hudIcon, mouseIcon] {
            icon.contentMode = .center
            icon.isUserInteractionEnabled = false
            addSubview(icon)
        }
        tintIcons()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setMode(_ newMode: ControlMode, animated: Bool) {
        guard newMode != mode else { return }
        mode = newMode
        let apply = { [weak self] in
            self?.layoutThumb()
            self?.tintIcons()
        }
        if animated {
            UIView.animate(withDuration: 0.22, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0, options: [], animations: apply)
        } else {
            apply()
        }
    }

    private func layoutThumb() {
        let half = bounds.width / 2
        thumb.frame = CGRect(
            x: mode == .hud ? 2 : half,
            y: 2,
            width: max(half - 2, 0),
            height: max(bounds.height - 4, 0)
        )
        thumb.layer.cornerRadius = thumb.bounds.height / 2
    }

    private func tintIcons() {
        hudIcon.tintColor = mode == .hud ? .black : UIColor.white.withAlphaComponent(0.75)
        mouseIcon.tintColor = mode == .mouse ? .black : UIColor.white.withAlphaComponent(0.75)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutThumb()
        let half = bounds.width / 2
        hudIcon.frame = CGRect(x: 0, y: 0, width: half, height: bounds.height)
        mouseIcon.frame = CGRect(x: half, y: 0, width: half, height: bounds.height)
    }
}

// MARK: - Thanh nhỏ sát mép trên màn hình: Setting + công tắc nhanh

final class TopBarView: UIView {
    let settingsButton = UIButton(type: .system)
    let modeToggle = ModeToggleView()
    let doneButton = UIButton(type: .system)

    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let divider = UIView()
    private let stack = UIStackView()
    private var dimItem: DispatchWorkItem?

    /// Độ mờ khi không thao tác
    private let idleAlpha: CGFloat = 0.38

    /// Đang mở bảng cài đặt
    var panelOpen = false {
        didSet { refreshAwake() }
    }

    /// Đang chỉnh sửa bố cục
    private var isEditing = false {
        didSet { refreshAwake() }
    }

    /// Giữ sáng (không tự mờ) khi đang mở bảng cài đặt hoặc chỉnh sửa bố cục
    private var keepAwake: Bool { panelOpen || isEditing }

    private func refreshAwake() {
        if keepAwake { wake() } else { scheduleDim() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 16
        layer.borderWidth = 1
        layer.borderColor = Neon.accent.withAlphaComponent(0.45).cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.35
        layer.shadowRadius = 6
        layer.shadowOffset = CGSize(width: 0, height: 2)

        blur.translatesAutoresizingMaskIntoConstraints = false
        blur.clipsToBounds = true
        blur.layer.cornerRadius = 16
        addSubview(blur)

        let cfg = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        settingsButton.setImage(UIImage(systemName: "gearshape.fill", withConfiguration: cfg), for: .normal)
        settingsButton.tintColor = .white

        divider.backgroundColor = UIColor.white.withAlphaComponent(0.2)

        var doneCfg = UIButton.Configuration.filled()
        doneCfg.title = "Xong"
        doneCfg.baseBackgroundColor = Neon.accent
        doneCfg.baseForegroundColor = .black
        doneCfg.cornerStyle = .capsule
        doneCfg.contentInsets = NSDirectionalEdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10)
        doneCfg.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont.systemFont(ofSize: 12, weight: .heavy)
            return outgoing
        }
        doneButton.configuration = doneCfg
        doneButton.isHidden = true

        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        for v in [settingsButton, divider, modeToggle, doneButton] as [UIView] { stack.addArrangedSubview(v) }
        addSubview(stack)

        modeToggle.translatesAutoresizingMaskIntoConstraints = false
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        divider.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            blur.topAnchor.constraint(equalTo: topAnchor),
            blur.bottomAnchor.constraint(equalTo: bottomAnchor),
            blur.leadingAnchor.constraint(equalTo: leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: trailingAnchor),

            stack.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),

            settingsButton.widthAnchor.constraint(equalToConstant: 32),
            settingsButton.heightAnchor.constraint(equalToConstant: 26),
            divider.widthAnchor.constraint(equalToConstant: 1),
            divider.heightAnchor.constraint(equalToConstant: 16),
            modeToggle.widthAnchor.constraint(equalToConstant: 68),
            modeToggle.heightAnchor.constraint(equalToConstant: 26),
        ])

        for control in [settingsButton, modeToggle, doneButton] as [UIControl] {
            control.addTarget(self, action: #selector(userTouched), for: .touchDown)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func userTouched() { wake() }

    /// Sáng rõ ngay, rồi tự mờ nhẹ sau 2.5 giây không thao tác
    func wake() {
        dimItem?.cancel()
        UIView.animate(withDuration: 0.15) { self.alpha = 1 }
        scheduleDim()
    }

    func scheduleDim() {
        dimItem?.cancel()
        guard !keepAwake else { return }
        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.keepAwake else { return }
            UIView.animate(withDuration: 0.5) { self.alpha = self.idleAlpha }
        }
        dimItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: item)
    }

    func update(mode: ControlMode, editing: Bool) {
        let changed = modeToggle.mode != mode || doneButton.isHidden == editing
        modeToggle.setMode(mode, animated: window != nil)
        doneButton.isHidden = !editing
        isEditing = editing
        if changed { wake() }
    }
}

// MARK: - Bảng cài đặt kiểu gaming

final class GamingPanelView: UIView {
    private unowned let host: WebViewController
    private let card = UIView()
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private var modeSegment: UISegmentedControl?

    init(host: WebViewController) {
        self.host = host
        super.init(frame: .zero)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: Dựng khung

    private func build() {
        backgroundColor = UIColor.black.withAlphaComponent(0.4)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(backgroundTapped(_:))))

        card.backgroundColor = Neon.panel
        card.layer.cornerRadius = 18
        card.layer.borderWidth = 1
        card.layer.borderColor = Neon.accent.withAlphaComponent(0.55).cgColor
        card.layer.shadowColor = Neon.accent.cgColor
        card.layer.shadowOpacity = 0.35
        card.layer.shadowRadius = 18
        card.layer.shadowOffset = .zero
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)

        // Tiêu đề
        let title = UILabel()
        let titleText = NSMutableAttributedString(
            string: "HK",
            attributes: [.font: UIFont.systemFont(ofSize: 20, weight: .black), .foregroundColor: Neon.accent]
        )
        titleText.append(NSAttributedString(
            string: "now",
            attributes: [.font: UIFont.systemFont(ofSize: 20, weight: .black), .foregroundColor: UIColor.white]
        ))
        title.attributedText = titleText
        let subtitle = UILabel()
        subtitle.attributedText = NSAttributedString(
            string: "BẢNG ĐIỀU KHIỂN",
            attributes: [.font: UIFont.systemFont(ofSize: 10, weight: .heavy), .foregroundColor: Neon.sub, .kern: 2.0]
        )
        let titleStack = UIStackView(arrangedSubviews: [title, subtitle])
        titleStack.axis = .vertical
        titleStack.spacing = 0

        let close = UIButton(type: .system)
        close.setImage(
            UIImage(systemName: "xmark.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 24, weight: .regular)),
            for: .normal
        )
        close.tintColor = Neon.sub
        close.addAction(UIAction { [weak self] _ in self?.host.dismissSettingsPanel() }, for: .touchUpInside)
        close.setContentHuggingPriority(.required, for: .horizontal)

        let header = UIStackView(arrangedSubviews: [titleStack, close])
        header.axis = .horizontal
        header.alignment = .center
        header.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(header)

        // Phần cuộn
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsVerticalScrollIndicator = false
        scroll.alwaysBounceVertical = true
        card.addSubview(scroll)

        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        let fit = scroll.heightAnchor.constraint(equalTo: scroll.contentLayoutGuide.heightAnchor)
        fit.priority = UILayoutPriority(750)

        let widthConstraint = card.widthAnchor.constraint(equalToConstant: 360)
        widthConstraint.priority = UILayoutPriority(999)

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: centerXAnchor),
            card.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 44),
            card.bottomAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.bottomAnchor, constant: -8),
            widthConstraint,
            card.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -24),

            header.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            header.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),

            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8),
            fit,

            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 2),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -10),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -14),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -28),
        ])

        populate()
    }

    @objc private func backgroundTapped(_ g: UITapGestureRecognizer) {
        if !card.frame.contains(g.location(in: self)) { host.dismissSettingsPanel() }
    }

    func animateIn() {
        alpha = 0
        card.transform = CGAffineTransform(translationX: 0, y: -10).scaledBy(x: 0.97, y: 0.97)
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut]) {
            self.alpha = 1
            self.card.transform = .identity
        }
    }

    func animateOut() {
        UIView.animate(withDuration: 0.15, animations: {
            self.alpha = 0
            self.card.transform = CGAffineTransform(translationX: 0, y: -8)
        }, completion: { _ in
            self.removeFromSuperview()
        })
    }

    /// Công tắc nhanh ở thanh trên vừa đổi chế độ -> cập nhật ô chọn chế độ trong bảng
    func syncState() {
        modeSegment?.selectedSegmentIndex = host.controlMode == .hud ? 0 : 1
    }

    // MARK: Nội dung

    private func populate() {
        let s = PadStore.shared.settings
        let host = self.host

        // --- CHẾ ĐỘ ---
        addSection("CHẾ ĐỘ")
        let modes = segmented(["Chiến đấu", "Chuột / Launcher"], selected: host.controlMode == .hud ? 0 : 1) { i in
            host.setControlMode(i == 0 ? .hud : .mouse)
        }
        modeSegment = modes
        add(modes)
        add(caption("Chiến đấu: hiện nút ảo, vùng trống để vuốt xoay camera. Chuột / Launcher: ẩn nút, chạm hoặc kéo ngón tay để rê và bấm chuột trong Steam / Epic."))
        add(caption("Kiểu chạm ở chế độ Chuột"))
        add(segmented(["Con trỏ ảo", "Chạm gốc"], selected: s.mouseStyle == .virtualCursor ? 0 : 1) { i in
            PadStore.shared.settings.mouseStyle = (i == 0) ? .virtualCursor : .native
            host.commitPad()
        })

        // --- ĐIỀU KHIỂN ---
        addSection("ĐIỀU KHIỂN")
        add(tile(toggleRow("Bộ điều khiển ảo", symbol: "gamecontroller.fill", isOn: s.enabled) { on in
            PadStore.shared.settings.enabled = on
            host.commitPad()
        }))
        add(tile(toggleRow("Bàn phím ảo iOS", symbol: "keyboard", isOn: host.keyField.isFirstResponder) { _ in
            host.toggleKeyboard()
        }))
        add(tile(toggleRow("Ẩn HUD (chạm tự do menu game)", symbol: "eye.slash", isOn: host.overlay.hudHidden) { _ in
            host.perform(.toggleHUD, down: true)
        }))
        add(caption("Chế độ nhập liệu"))
        add(segmented(InputMode.allCases.map { $0.shortTitle }, selected: host.inputMode.rawValue) { i in
            if let m = InputMode(rawValue: i) { host.inputMode = m }
        })

        // --- CAMERA & GYRO ---
        addSection("CAMERA & GYRO")
        add(tile(sliderRow("Độ nhạy vuốt", lo: 0.3, hi: 3.0, value: Float(s.lookSensitivity),
                           format: { String(format: "%.2fx", $0) },
                           live: { PadStore.shared.settings.lookSensitivity = CGFloat(($0 * 20).rounded() / 20) },
                           commit: { PadStore.shared.save() })))
        add(caption("Gyro (nghiêng máy để ngắm)"))
        let gyroIndex: Int
        switch s.gyroMode {
        case .off: gyroIndex = 0
        case .always: gyroIndex = 1
        case .whileAiming: gyroIndex = 2
        }
        add(segmented(["Tắt", "Luôn bật", "Khi ngắm"], selected: gyroIndex) { i in
            PadStore.shared.settings.gyroMode = [GyroMode.off, .always, .whileAiming][i]
            host.commitPad()
        })
        add(tile(sliderRow("Độ nhạy gyro", lo: 0.5, hi: 4.0, value: Float(s.gyroSensitivity),
                           format: { String(format: "%.2fx", $0) },
                           live: { PadStore.shared.settings.gyroSensitivity = CGFloat(($0 * 20).rounded() / 20) },
                           commit: { PadStore.shared.save() })))
        add(tile(toggleRow("Đảo hướng ngang gyro", symbol: "arrow.left.and.right", isOn: s.gyroInvertX) { on in
            PadStore.shared.settings.gyroInvertX = on
            host.commitPad()
        }))
        add(tile(toggleRow("Đảo hướng dọc gyro", symbol: "arrow.up.and.down", isOn: s.gyroInvertY) { on in
            PadStore.shared.settings.gyroInvertY = on
            host.commitPad()
        }))

        // --- HIỂN THỊ ---
        addSection("HIỂN THỊ")
        add(tile(sliderRow("Độ đậm của nút", lo: 0.2, hi: 1.0, value: Float(s.opacity),
                           format: { "\(Int(($0 * 100).rounded()))%" },
                           live: { v in
                               PadStore.shared.settings.opacity = CGFloat(v)
                               if !host.padEditing, host.controlMode == .hud { host.overlay.alpha = CGFloat(v) }
                           },
                           commit: { PadStore.shared.save() })))

        // --- BỐ CỤC & TIỆN ÍCH ---
        addSection("BỐ CỤC & TIỆN ÍCH")
        let editTitle = host.padEditing ? "Xong chỉnh sửa" : "Chỉnh sửa bố cục"
        let edit = tileButton(editTitle, symbol: host.padEditing ? "checkmark" : "slider.horizontal.3") {
            host.dismissSettingsPanel()
            host.setControlMode(.hud)
            host.padEditing.toggle()
            if !host.padEditing { PadStore.shared.save() }
        }
        let addBtn = tileButton("Thêm nút…", symbol: "plus.circle") {
            host.dismissSettingsPanel()
            host.setControlMode(.hud)
            host.addButtonFlow()
        }
        let release = tileButton("Thả chuột", symbol: "cursorarrow") {
            host.dismissSettingsPanel()
            host.webView.evaluateJavaScript("document.exitPointerLock&&document.exitPointerLock()")
        }
        let reload = tileButton("Tải lại trang", symbol: "arrow.clockwise") {
            host.dismissSettingsPanel()
            host.webView.reload()
        }
        let reset = tileButton("Đặt lại bố cục mặc định", symbol: "arrow.uturn.backward", tint: Neon.warn) {
            host.dismissSettingsPanel()
            let alert = UIAlertController(
                title: "Đặt lại bố cục?",
                message: "Toàn bộ nút và cài đặt điều khiển sẽ về mặc định.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
            alert.addAction(UIAlertAction(title: "Đặt lại", style: .destructive) { _ in
                PadStore.shared.settings = PadSettings()
                host.commitPad()
            })
            host.present(alert, animated: true)
        }
        addRow([edit, addBtn])
        addRow([release, reload])
        addRow([reset])
        add(caption("Chạm vùng tối bên ngoài để đóng bảng."))
    }

    // MARK: Thành phần giao diện

    private func add(_ v: UIView) { stack.addArrangedSubview(v) }

    private func addRow(_ views: [UIView]) {
        let row = UIStackView(arrangedSubviews: views)
        row.axis = .horizontal
        row.spacing = 8
        row.distribution = .fillEqually
        add(row)
    }

    private func addSection(_ text: String) {
        if let last = stack.arrangedSubviews.last { stack.setCustomSpacing(18, after: last) }
        let l = UILabel()
        l.attributedText = NSAttributedString(
            string: text,
            attributes: [.font: UIFont.systemFont(ofSize: 11, weight: .heavy), .foregroundColor: Neon.accent, .kern: 1.6]
        )
        add(l)
    }

    private func caption(_ text: String) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = .systemFont(ofSize: 11, weight: .regular)
        l.textColor = Neon.sub
        l.numberOfLines = 0
        return l
    }

    private func segmented(_ titles: [String], selected: Int, onChange: @escaping (Int) -> Void) -> UISegmentedControl {
        let sc = UISegmentedControl(items: titles)
        sc.selectedSegmentIndex = selected
        sc.backgroundColor = Neon.row
        sc.selectedSegmentTintColor = Neon.accent
        sc.setTitleTextAttributes(
            [.foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 12, weight: .semibold)], for: .normal
        )
        sc.setTitleTextAttributes(
            [.foregroundColor: UIColor.black, .font: UIFont.systemFont(ofSize: 12, weight: .heavy)], for: .selected
        )
        sc.addAction(UIAction { [weak sc] _ in
            if let sc { onChange(sc.selectedSegmentIndex) }
        }, for: .valueChanged)
        sc.heightAnchor.constraint(equalToConstant: 34).isActive = true
        return sc
    }

    private func tile(_ content: UIView) -> UIView {
        let box = UIView()
        box.backgroundColor = Neon.row
        box.layer.cornerRadius = 10
        content.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: box.topAnchor, constant: 6),
            content.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -6),
            content.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 12),
            content.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -10),
        ])
        return box
    }

    private func toggleRow(_ title: String, symbol: String, isOn: Bool, onChange: @escaping (Bool) -> Void) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = Neon.accent
        icon.contentMode = .scaleAspectFit
        icon.widthAnchor.constraint(equalToConstant: 22).isActive = true
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .white
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.75
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let sw = UISwitch()
        sw.isOn = isOn
        sw.onTintColor = Neon.accent
        sw.setContentHuggingPriority(.required, for: .horizontal)
        sw.addAction(UIAction { [weak sw] _ in
            if let sw { onChange(sw.isOn) }
        }, for: .valueChanged)

        let row = UIStackView(arrangedSubviews: [icon, label, sw])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 10
        return row
    }

    private func sliderRow(
        _ title: String, lo: Float, hi: Float, value: Float,
        format: @escaping (Float) -> String,
        live: @escaping (Float) -> Void,
        commit: @escaping () -> Void
    ) -> UIView {
        let name = UILabel()
        name.text = title
        name.font = .systemFont(ofSize: 14, weight: .medium)
        name.textColor = .white
        name.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let val = UILabel()
        val.text = format(value)
        val.font = .monospacedDigitSystemFont(ofSize: 13, weight: .bold)
        val.textColor = Neon.accent
        val.setContentHuggingPriority(.required, for: .horizontal)

        let top = UIStackView(arrangedSubviews: [name, val])
        top.axis = .horizontal

        let slider = UISlider()
        slider.minimumValue = lo
        slider.maximumValue = hi
        slider.value = value
        slider.minimumTrackTintColor = Neon.accent
        slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.18)
        slider.addAction(UIAction { [weak slider, weak val] _ in
            guard let slider, let val else { return }
            val.text = format(slider.value)
            live(slider.value)
        }, for: .valueChanged)
        slider.addAction(UIAction { _ in commit() }, for: [.touchUpInside, .touchUpOutside, .touchCancel])

        let col = UIStackView(arrangedSubviews: [top, slider])
        col.axis = .vertical
        col.spacing = 2
        return col
    }

    private func tileButton(_ title: String, symbol: String, tint: UIColor = .white, action: @escaping () -> Void) -> UIButton {
        var c = UIButton.Configuration.plain()
        c.title = title
        c.image = UIImage(systemName: symbol)
        c.imagePadding = 6
        c.baseForegroundColor = tint
        c.titleLineBreakMode = .byTruncatingTail
        c.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
            return outgoing
        }
        c.background.backgroundColor = Neon.row
        c.background.cornerRadius = 10
        c.background.strokeColor = tint == .white ? UIColor.white.withAlphaComponent(0.12) : tint.withAlphaComponent(0.6)
        c.background.strokeWidth = 1
        let b = UIButton(configuration: c, primaryAction: UIAction { _ in action() })
        b.heightAnchor.constraint(equalToConstant: 42).isActive = true
        return b
    }
}
