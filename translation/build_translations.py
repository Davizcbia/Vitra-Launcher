"""Build the frontend translation from the spreadsheet.

Reads "Vitra 界面翻译.xlsx" (sheet 界面文字: English in column C, Chinese in D),
writes core/launcher/project-glass/i18n/projectglass_<code>.ts for Simplified Chinese
(column D) and every further language column (see auto_translate.py), in the
context "ProjectGlass" that the QML tr() and C++ pgTr() use, and compiles them
with Qt's lrelease. The launcher loads the file for its language (PrismBridge.h).
build_windows.cmd runs this before every build; when the sheet has not changed
the files are left untouched, so the build does not re-embed them.

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

sheet = load_workbook(workbook, read_only=True)["界面文字"]
all_rows = list(sheet.iter_rows(values_only=True))
header = [str(h or "") for h in all_rows[0]]
rows = all_rows[1:]

# Column D is the human Simplified Chinese; columns from G on are further
# languages headed "<Qt locale code> <name>" (filled by auto_translate.py).
languages = {"zh_CN": 3}
for index, title in enumerate(header):
    code = title.split(" ")[0]
    if index >= 6 and code:
        languages[code] = index

out_dir.mkdir(parents=True, exist_ok=True)
for code, column in languages.items():
    messages = [(row[2], row[column]) for row in rows if len(row) > column and row[2] and row[column]]
    ts = out_dir / f"projectglass_{code}.ts"
    qm = ts.with_suffix(".qm")
    body = "".join(
        f"    <message>\n        <source>{escape(str(en))}</source>\n        <translation>{escape(str(tr))}</translation>\n    </message>\n"
        for en, tr in messages)
    text = ('<?xml version="1.0" encoding="utf-8"?>\n<!DOCTYPE TS>\n'
            f'<TS version="2.1" language="{code}">\n'
            f"<context>\n    <name>ProjectGlass</name>\n{body}</context>\n</TS>\n")
    unchanged = ts.exists() and ts.read_text(encoding="utf-8") == text
    if unchanged and qm.exists() and qm.stat().st_mtime >= ts.stat().st_mtime:
        print(f"{code}: {len(messages)} messages, translation unchanged")
        continue
    if not unchanged:
        ts.write_text(text, encoding="utf-8")
    subprocess.run([lrelease, "-silent", str(ts), "-qm", str(qm)], check=True)
    print(f"{code}: {len(messages)} messages -> {qm.name}")
