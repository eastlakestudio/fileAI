#!/usr/bin/env python3
"""从 Support/Localizable.xcstrings 生成 .lproj/Localizable.strings 并部署到指定目录。
用法: python3 gen_lproj.py <目标目录>
调试:  python3 gen_lproj.py .build/debug
打包:  python3 gen_lproj.py "<App>.app/Contents/Resources"
"""
import json, sys, os

XCSTRINGS = os.path.join(os.path.dirname(__file__), "..", "Support", "Localizable.xcstrings")

def esc(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")

def main(target_dir: str):
    with open(XCSTRINGS, encoding="utf-8") as f:
        doc = json.load(f)
    for lang in ("zh-Hans", "en"):
        lproj = os.path.join(target_dir, f"{lang}.lproj")
        os.makedirs(lproj, exist_ok=True)
        lines = ["/* Generated from Localizable.xcstrings — do not edit manually */"]
        count = 0
        for key, entry in sorted(doc.get("strings", {}).items()):
            unit = (entry.get("localizations", {}).get(lang, {}) or {}).get("stringUnit", {})
            value = unit.get("value")
            if value is None:
                value = key  # 缺失译文回退 key（中文）
            lines.append(f'"{esc(key)}" = "{esc(value)}";')
            count += 1
        out = os.path.join(lproj, "Localizable.strings")
        with open(out, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
        print(f"{out}: {count} entries")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__); sys.exit(1)
    main(sys.argv[1])
