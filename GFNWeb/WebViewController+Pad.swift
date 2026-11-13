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
            gearButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 10),
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

        let test = UIAction(
            title: "Thử vuốt toàn màn hình (ngoài game)",
            image: UIImage(systemName: "hand.draw"),
            state: padTestMode ? .on : .off
        ) { [weak self] _ in
            self?.padTestMode.toggle()
        }

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
            UIMenu(title: "", options: .displayInline, children: [toggle, edit, add, test]),
            UIMenu(title: "", options: .displayInline, children: [gyroMode, gyroSens, gyroInvX, gyroInvY]),
            UIMenu(title: "", options: .displayInline, children: [lookSens, opacity]),
            UIMenu(title: "", options: .displayInline, children: [releaseLock, reload, reset]),
        ])
    }

    // MARK: - Thêm nút

    func addButtonFlow() {
        presentActionChooser(title: "Chọn hành động cho nút mới", source: gearButton) { [weak self] action in
            guard let self else { return }
            let button = PadButton(label: action.defaultLabel, action: action, x: 0.5, y: 0.5, size: 64)
            PadStore.shared.settings.buttons.append(button)
            PadStore.shared.save()
            self.overlay.reload()
            self.padEditing = true     // bật chế độ chỉnh sửa để kéo nút tới chỗ mong muốn
        }
    }

    // MARK: - Hộp thoại chọn hành động

    func presentActionChooser(title: String, source: UIView, completion: @escaping (PadAction) -> Void) {
        let sheet = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)
        for (name, action) in PadAction.presets {
            sheet.addAction(UIAlertAction(title: name, style: .default) { _ in completion(action) })
        }
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
