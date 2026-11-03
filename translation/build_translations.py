"""Build the frontend translation from the spreadsheet.

Reads "Vitra 界面翻译.xlsx" (sheet 界面文字: English in column C, Chinese in D),
writes core/launcher/project-glass/i18n/projectglass_zh_CN.ts (context "ProjectGlass",
the context the QML tr() and C++ pgTr() use) and compiles it with Qt's lrelease.

Usage: python translation/build_translations.py [path to lrelease]
Needs openpyxl (pip install openpyxl). Rows with an empty Chinese cell stay English.
"""
import subprocess
import sys
from pathlib import Path
from xml.sax.saxutils import escape

from openpyxl import load_workbook

here = Path(__file__).resolve().parent
workbook = here / "Vitra 界面翻译.xlsx"
out_dir = here.parent / "core" / "launcher" / "project-glass" / "i18n"
lrelease = sys.argv[1] if len(sys.argv) > 1 else r"C:\Qt\6.12.0\msvc2022_64\bin\lrelease.exe"

rows = load_workbook(workbook, read_only=True)["界面文字"].iter_rows(min_row=2, values_only=True)
messages = [(english, chinese) for _, _, english, chinese, *_ in rows if english and chinese]

out_dir.mkdir(parents=True, exist_ok=True)
ts = out_dir / "projectglass_zh_CN.ts"
body = "".join(
    f"    <message>\n        <source>{escape(en)}</source>\n        <translation>{escape(zh)}</translation>\n    </message>\n"
    for en, zh in messages)
ts.write_text('<?xml version="1.0" encoding="utf-8"?>\n<!DOCTYPE TS>\n<TS version="2.1" language="zh_CN">\n'
              f"<context>\n    <name>ProjectGlass</name>\n{body}</context>\n</TS>\n", encoding="utf-8")
subprocess.run([lrelease, str(ts), "-qm", str(ts.with_suffix(".qm"))], check=True)
print(f"{len(messages)} messages -> {ts.with_suffix('.qm')}")
