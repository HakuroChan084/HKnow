# HKnow

Ứng dụng bọc GeForce NOW, có bộ điều khiển ảo (tay cầm Xbox 360 ảo, joystick, vùng xoay camera, gyro, bàn phím ảo).

- `GFNWeb/` + `project.yml`: bản **iOS** (Swift/UIKit) -> artifact `GFNWeb-ipa`
- `android/`: bản **Android** (Kotlin) -> artifact `HKnow-apk`
- Đoạn JS chèn vào trang (tay cầm ảo) dùng **chung**: sửa trong `GFNWeb/WebViewController.swift`
  (`injectedJS`), CI tự chép sang `android/app/src/main/assets/inject.js` bằng `tools/sync_js.py`.
  Build local Android: chạy `python3 tools/sync_js.py` trước.
- Workflow `build.yml` (chạy tay, chọn nhánh) build cả hai bản.
