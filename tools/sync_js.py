#!/usr/bin/env python3
"""Lấy đoạn JS chèn vào trang từ bản iOS (WebViewController.swift) sang assets của bản Android.
Sửa JS MỘT chỗ (file Swift) rồi chạy lại script này; CI cũng tự chạy trước khi build APK."""
import re, sys, pathlib

root = pathlib.Path(__file__).resolve().parent.parent
src = (root / "GFNWeb" / "WebViewController.swift").read_text(encoding="utf-8")
m = re.search(r'injectedJS = #"""\n(.*?)\n\s*"""#', src, re.S)
if not m:
    sys.exit("Không tìm thấy injectedJS trong WebViewController.swift")
lines = m.group(1).split("\n")
# bỏ phần thụt lề chung của chuỗi Swift
indent = min((len(l) - len(l.lstrip())) for l in lines if l.strip())
js = "\n".join(l[indent:] if l.strip() else "" for l in lines) + "\n"
out = root / "android" / "app" / "src" / "main" / "assets" / "inject.js"
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(js, encoding="utf-8")
print(f"OK: {out} ({len(js)} ký tự)")
