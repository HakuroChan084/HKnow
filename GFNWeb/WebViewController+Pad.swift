import UIKit
import WebKit

// Menu (nút tay cầm ở góc trái trên) + các hộp thoại chỉnh sửa nút
extension WebViewController {

    // MARK: - Nút menu

    func setupGearButton() {
        gearButton.setImage(UIImage(systemName: "gamecontroller.fill"), for: .normal)
        gearButton.tintColor = .white
        gearButton.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        gearButton.layer.cornerRadius = 18
        gearButton.alpha = 0.7
        gearButton.showsMenuAsPrimaryAction = true
        gearButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(gearButton)
        NSLayoutConstraint.activate([
            gearButton.widthAnchor.constraint(equalToConstant: 36),
            gearButton.heightAnchor.constraint(equalToConstant: 36),
            gearButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            gearButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
        ])
        refreshMenu()
    }

    private func commitPad() {
        PadStore.shared.save()
        overlay.reload()
        applyPadState()
    }

    func refreshMenu() {
        guard isViewLoaded else { return }
        let store = PadStore.shared
        let s = store.settings

        func valueMenu(
            _ title: String, _ values: [CGFloat], current: CGFloat,
            format: @escaping (CGFloat) -> String, set: @escaping (CGFloat) -> Void
        ) -> UIMenu {
            let actions = values.map { v in
                UIAction(title: format(v), state: abs(v - current) < 0.01 ? .on : .off) { [weak self] _ in
                    set(v)
                    self?.commitPad()
                }
            }
            return UIMenu(title: title, children: actions)
        }

        let toggle = UIAction(title: "Bộ điều khiển ảo", state: s.enabled ? .on : .off) { [weak self] _ in
            store.settings.enabled.toggle()
            self?.commitPad()
        }

        let edit = UIAction(
            title: padEditing ? "Xong chỉnh sửa" : "Chỉnh sửa bố cục",
            image: UIImage(systemName: padEditing ? "checkmark" : "slider.horizontal.3")
        ) { [weak self] _ in
            guard let self else { return }
            self.padEditing.toggle()
            if !self.padEditing { store.save() }
        }

        let add = UIAction(title: "Thêm nút…", image: UIImage(systemName: "plus.circle")) { [weak self] _ in
            self?.addButtonFlow()
        }

        let keyboard = UIAction(
            title: keyField.isFirstResponder ? "Tắt bàn phím ảo" : "Bật bàn phím ảo",
            image: UIImage(systemName: "keyboard")
        ) { [weak self] _ in
            self?.toggleKeyboard()
        }

        let touchMouse = UIAction(
            title: "Chạm = chuột (khi game khóa chuột)",
            image: UIImage(systemName: "hand.point.up.left"),
            state: s.touchMouse ? .on : .off
        ) { [weak self] _ in
            store.settings.touchMouse.toggle()
            self?.commitPad()
        }

        let hideHUD = UIAction(
            title: overlay.hudHidden ? "Hiện HUD" : "Ẩn HUD (chạm tự do vào menu game)",
            image: UIImage(systemName: overlay.hudHidden ? "eye" : "eye.slash")
        ) { [weak self] _ in
            guard let self else { return }
            self.perform(.toggleHUD, down: true)
        }

        let inputModeMenu = UIMenu(
            title: "Chế độ nhập liệu",
            image: UIImage(systemName: "gamecontroller"),
            children: InputMode.allCases.map { mode in
                UIAction(title: mode.title, state: self.inputMode == mode ? .on : .off) { [weak self] _ in
                    self?.inputMode = mode
                }
            }
        )

        let gyroMode = UIMenu(title: "Gyro (nghiêng máy để ngắm)", children: [
            UIAction(title: "Tắt", state: s.gyroMode == .off ? .on : .off) { [weak self] _ in
                store.settings.gyroMode = .off; self?.commitPad()
            },
            UIAction(title: "Luôn bật", state: s.gyroMode == .always ? .on : .off) { [weak self] _ in
                store.settings.gyroMode = .always; self?.commitPad()
            },
            UIAction(title: "Chỉ khi giữ nút Ngắm (chuột phải)", state: s.gyroMode == .whileAiming ? .on : .off) { [weak self] _ in
                store.settings.gyroMode = .whileAiming; self?.commitPad()
            },
        ])

        let gyroSens = valueMenu(
            "Độ nhạy gyro", [0.5, 1, 1.5, 2, 3, 4], current: s.gyroSensitivity,
            format: { "\($0)x" }, set: { store.settings.gyroSensitivity = $0 }
        )

        let gyroInvX = UIAction(title: "Đảo hướng ngang gyro", state: s.gyroInvertX ? .on : .off) { [weak self] _ in
            store.settings.gyroInvertX.toggle(); self?.commitPad()
        }
        let gyroInvY = UIAction(title: "Đảo hướng dọc gyro", state: s.gyroInvertY ? .on : .off) { [weak self] _ in
            store.settings.gyroInvertY.toggle(); self?.commitPad()
        }

        let lookSens = valueMenu(
            "Độ nhạy vuốt màn hình", [0.5, 0.75, 1, 1.5, 2, 3], current: s.lookSensitivity,
            format: { "\($0)x" }, set: { store.settings.lookSensitivity = $0 }
        )

        let opacity = valueMenu(
            "Độ đậm của nút", [0.3, 0.45, 0.6, 0.8, 1.0], current: s.opacity,
            format: { "\(Int($0 * 100))%" }, set: { store.settings.opacity = $0 }
        )

        let releaseLock = UIAction(title: "Thả chuột / chạm vào menu GFN", image: UIImage(systemName: "cursorarrow")) { [weak self] _ in
            self?.webView.evaluateJavaScript("document.exitPointerLock&&document.exitPointerLock()")
        }

        let reload = UIAction(title: "Tải lại trang", image: UIImage(systemName: "arrow.clockwise")) { [weak self] _ in
            self?.webView.reload()
        }

        let reset = UIAction(
            title: "Đặt lại bố cục mặc định",
            image: UIImage(systemName: "arrow.uturn.backward"), attributes: .destructive
        ) { [weak self] _ in
            store.settings = PadSettings()
            self?.commitPad()
        }

        gearButton.menu = UIMenu(title: "", children: [
            UIMenu(title: "", options: .displayInline, children: [toggle, inputModeMenu, edit, add, keyboard, hideHUD, touchMouse]),
            UIMenu(title: "", options: .displayInline, children: [gyroMode, gyroSens, gyroInvX, gyroInvY]),
            UIMenu(title: "", options: .displayInline, children: [lookSens, opacity]),
            UIMenu(title: "", options: .displayInline, children: [releaseLock, reload, reset]),
        ])
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

    /// Bảng chọn hành động kiểu cũ: danh sách hay dùng + "Tất cả phím & nút tay cầm" (theo nhóm) + "Phím khác…"
    func presentActionChooser(title: String, source: UIView, completion: @escaping (PadAction) -> Void) {
        let sheet = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)
        for (name, action) in PadAction.presets {
            sheet.addAction(UIAlertAction(title: name, style: .default) { _ in completion(action) })
        }
        sheet.addAction(UIAlertAction(title: "Tất cả phím & nút tay cầm…", style: .default) { [weak self] _ in
            self?.presentGroupChooser(source: source, completion: completion)
        })
        sheet.addAction(UIAlertAction(title: "Phím khác…", style: .default) { [weak self] _ in
            self?.askCustomKey(completion)
        })
        sheet.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = source
            pop.sourceRect = source.bounds
        }
        present(sheet, animated: true)
    }

    /// Chọn nhóm (tay cầm, phím bổ trợ, F1–F12, A–Z...) rồi chọn phím trong nhóm
    private func presentGroupChooser(source: UIView, completion: @escaping (PadAction) -> Void) {
        let sheet = UIAlertController(title: "Chọn nhóm", message: nil, preferredStyle: .actionSheet)
        for group in PadAction.catalog {
            sheet.addAction(UIAlertAction(title: group.title, style: .default) { [weak self] _ in
                let list = UIAlertController(title: group.title, message: nil, preferredStyle: .actionSheet)
                for item in group.items {
                    let name = item.detail.map { "\(item.label) — \($0)" } ?? item.label
                    list.addAction(UIAlertAction(title: name, style: .default) { _ in completion(item.action) })
                }
                list.addAction(UIAlertAction(title: "Hủy", style: .cancel))
                if let pop = list.popoverPresentationController {
                    pop.sourceView = source
                    pop.sourceRect = source.bounds
                }
                self?.present(list, animated: true)
            })
        }
        sheet.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = source
            pop.sourceRect = source.bounds
        }
        present(sheet, animated: true)
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
        let sheet = UIAlertController(title: "\(b.label) — \(b.action.title)", message: nil, preferredStyle: .actionSheet)

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
        sheet.addAction(UIAlertAction(title: "Phóng to", style: .default) { [weak self] _ in
            self?.mutateButton(id) { $0.size = min($0.size * 1.2, 220) }
        })
        sheet.addAction(UIAlertAction(title: "Thu nhỏ", style: .default) { [weak self] _ in
            self?.mutateButton(id) { $0.size = max($0.size / 1.2, 36) }
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

    /// Chỉnh vùng vuốt xoay camera: phóng to / thu nhỏ theo cả khung, chiều ngang hoặc chiều dọc
    func presentLookPadEditor(from source: UIView) {
        func resize(_ dw: CGFloat, _ dh: CGFloat) {
            var s = PadStore.shared.settings
            s.lookWidth *= dw
            s.lookHeight *= dh
            s.clampLookPad()
            PadStore.shared.settings = s
            commitPad()
        }
        let sheet = UIAlertController(title: "Vùng xoay camera", message: "Kéo khung để di chuyển", preferredStyle: .actionSheet)
        let items: [(String, CGFloat, CGFloat)] = [
            ("Phóng to cả khung", 1.15, 1.15), ("Thu nhỏ cả khung", 1 / 1.15, 1 / 1.15),
            ("Rộng hơn (ngang)", 1.15, 1), ("Hẹp lại (ngang)", 1 / 1.15, 1),
            ("Cao hơn (dọc)", 1, 1.15), ("Thấp lại (dọc)", 1, 1 / 1.15),
        ]
        for (title, dw, dh) in items {
            sheet.addAction(UIAlertAction(title: title, style: .default) { _ in resize(dw, dh) })
        }
        sheet.addAction(UIAlertAction(title: "Đặt lại vị trí & kích thước", style: .destructive) { [weak self] _ in
            PadStore.shared.settings.resetLookPad()
            self?.commitPad()
        })
        sheet.addAction(UIAlertAction(title: "Xong", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = source
            pop.sourceRect = source.bounds
        }
        present(sheet, animated: true)
    }

    func presentJoystickEditor(from source: UIView) {
        let sheet = UIAlertController(title: "Joystick đi (W A S D)", message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Phóng to", style: .default) { [weak self] _ in
            PadStore.shared.settings.joySize = min(PadStore.shared.settings.joySize * 1.2, 300)
            self?.commitPad()
        })
        sheet.addAction(UIAlertAction(title: "Thu nhỏ", style: .default) { [weak self] _ in
            PadStore.shared.settings.joySize = max(PadStore.shared.settings.joySize / 1.2, 90)
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
