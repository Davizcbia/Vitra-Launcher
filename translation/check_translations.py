"""List interface text in project-glass that "Vitra 界面翻译.xlsx" does not translate.

build_windows.cmd runs this after build_translations.py and prints the result;
it never fails the build. Add a row (English in C, Chinese in D) for each
string it lists, or add the string to IGNORED below if it should stay as is.

  direct    literal argument of tr(), pgTr() or qsTranslate("ProjectGlass", ...)
  indirect  literals in options/model arrays and title/caption/label-like keys,
            which reach tr() through modelData (may include non-interface text)

Usage: python translation/check_translations.py [--strict]
  --strict  exit with status 1 when a direct string is missing
"""
import re
import sys
from pathlib import Path

from openpyxl import load_workbook

here = Path(__file__).resolve().parent
src = here.parent / "core" / "launcher" / "project-glass"
sheet = here / "Vitra 界面翻译.xlsx"

# Names, versions, colours and lab sample data: shown as written.
IGNORED = {
    "°", "GitHub", "Project Glass · 09.22 · Isolated Glass Lab", "The Rebirth", "Fabric 1.21.5",
    "Survival", "Minecraft 1.20.1", "Creative", "Minecraft 26.3", "#8E8E93", "#33FFFFFF", "#1F000000",
    # Language names (each in its own language) and translation services.
    "简体中文", "繁體中文", "English", "日本語", "한국어", "Русский", "Español", "Français", "Deutsch", "Português",
    "Google", "Microsoft Azure", "DeepL",
}

STR = r'"((?:[^"\\\n]|\\.)*)"'
DIRECT = [
    re.compile(r'\btr\(\s*' + STR),
    re.compile(r'\bpgTr\(\s*(?:QStringLiteral\(\s*)?' + STR),
    re.compile(r'qsTranslate\(\s*"ProjectGlass"\s*,\s*' + STR),
    re.compile(r'QT_TRANSLATE_NOOP\(\s*"ProjectGlass"\s*,\s*' + STR),
]
ARRAY = re.compile(r'\b(options|model|tabs|sections|choices|items|\w+Titles)\s*:\s*\[([^\]]*)\]')
PAIR = re.compile(r'\b(title|caption|label|name|unit|subtitle|placeholder|hint|description|detail)\s*:\s*' + STR)
LITERAL = re.compile(STR)
NOT_PROSE = re.compile(r'[#%\d.\s:/\\-]+|[a-z0-9_.\-]+(\.[a-z]{2,4})?|\d+(\.\d+)?\s*[KMG]i?B/s')


def unescape(s):
    return s.replace('\\"', '"').replace("\\\\", "\\").replace("\\n", "\n")


def main():
    known = {row[2] for row in load_workbook(sheet, read_only=True)["界面文字"].iter_rows(min_row=2, values_only=True)
             if row[2]}
    found = {}

    def add(text, kind, where):
        text = unescape(text)
        if not text.strip() or text in known or text in IGNORED:
            return
        if kind == "indirect" and NOT_PROSE.fullmatch(text):
            return
        item = found.setdefault(text, {"kind": kind, "where": []})
        if kind == "direct":
            item["kind"] = "direct"
        if len(item["where"]) < 3:
            item["where"].append(where)

    for path in sorted(src.rglob("*")):
        if path.suffix not in {".qml", ".js", ".h", ".cpp", ".inc"} or "platform" in path.parts or "tests" in path.parts:
            continue
        for number, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
            where = f"{path.name}:{number}"
            for pattern in DIRECT:
                for m in pattern.finditer(line):
                    add(m.group(1), "direct", where)
            if path.suffix in {".qml", ".js"}:
                for m in ARRAY.finditer(line):
                    for s in LITERAL.finditer(m.group(2)):
                        add(s.group(1), "indirect", where)
                for m in PAIR.finditer(line):
                    add(m.group(2), "indirect", where)

    if not found:
        print("Translation check: every interface string has a Chinese translation.")
        return 0
    direct = sum(item["kind"] == "direct" for item in found.values())
    print(f"Translation check: {len(found)} strings without Chinese ({direct} certain, "
          f"{len(found) - direct} to review). Add them to translation/Vitra 界面翻译.xlsx:")
    for text, item in found.items():
        print(f"  [{'missing' if item['kind'] == 'direct' else 'review '}] {text!r}  ({', '.join(item['where'])})")
    return 1 if direct and "--strict" in sys.argv else 0


if __name__ == "__main__":
    sys.exit(main())
