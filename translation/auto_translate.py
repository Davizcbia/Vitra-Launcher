"""Fill the extra interface languages in "Vitra 界面翻译.xlsx" by machine translation.

The sheet 界面文字 keeps English in column C and Simplified Chinese in D (human
translation). Each further language has its own column after F, headed with
its Qt locale code and name, e.g. "ja 日本語". This script adds missing
language columns and fills every EMPTY cell from the English text with Google
Translate; cells that already hold text (for example your own corrections)
are never changed. build_translations.py then builds one .qm per column.

A translation is only kept when it has the same placeholders (%1, %2, ...),
line breaks and leading/trailing spaces as the English; otherwise the cell
stays empty and the interface shows English for that string.

Usage: python translation/auto_translate.py [language codes...]
  e.g. python translation/auto_translate.py            (all languages below)
       python translation/auto_translate.py ja ko      (only these)
Needs openpyxl and network access. Run it after adding new rows.
"""
import json
import re
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

from openpyxl import load_workbook

here = Path(__file__).resolve().parent
workbook_path = here / "Vitra 界面翻译.xlsx"

# Qt locale code -> (header name, Google target)
LANGUAGES = {
    "zh_TW": ("繁體中文", "zh-TW"),
    "ja": ("日本語", "ja"),
    "ko": ("한국어", "ko"),
    "ru": ("Русский", "ru"),
    "es": ("Español", "es"),
    "fr": ("Français", "fr"),
    "de": ("Deutsch", "de"),
    "pt_BR": ("Português (Brasil)", "pt"),
}
FIRST_LANGUAGE_COLUMN = 7  # G; A-F are ID, category, English, Chinese, note, location
PLACEHOLDER = re.compile(r"%\d")
# Product and technical names that must stay as written.
KEEP = ["Vitra", "Liquid Glass", "Glass Lab", "Prism Launcher", "Prism", "Minecraft", "Modrinth", "CurseForge",
        "Fabric", "NeoForge", "Forge", "Quilt", "Java", "BMCLAPI", "MCIM", "Microsoft", "Azure", "DeepL", "Google",
        "GitHub", "options.txt"]


def protect(text):
    """Swaps kept names for tokens the translator leaves alone."""
    tokens = []
    def swap(match):
        tokens.append(match.group(0))
        return f"[{len(tokens) - 1}]"
    pattern = re.compile("|".join(re.escape(k) for k in sorted(KEEP, key=len, reverse=True)))
    return pattern.sub(swap, text), tokens


def restore(text, tokens):
    return re.sub(r"[\[［]\s*(\d+)\s*[\]］]", lambda m: tokens[int(m.group(1))] if int(m.group(1)) < len(tokens) else m.group(0), text)


def valid(source, result):
    if not result or not result.strip():
        return False
    if sorted(PLACEHOLDER.findall(source)) != sorted(PLACEHOLDER.findall(result)):
        return False
    if source.count("\n") != result.count("\n"):
        return False
    return True


def keep_spacing(source, result):
    lead = source[:len(source) - len(source.lstrip())]
    trail = source[len(source.rstrip()):]
    return lead + result.strip() + trail


def translate_batch(texts, target):
    body = "&".join("q=" + urllib.parse.quote(t) for t in texts).encode()
    url = "https://translate.googleapis.com/translate_a/t?client=gtx&sl=en&tl=" + urllib.parse.quote(target)
    request = urllib.request.Request(url, data=body, headers={"Content-Type": "application/x-www-form-urlencoded;charset=UTF-8"})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                data = json.loads(response.read().decode("utf-8"))
            if isinstance(data, str):
                data = [data]
            out = [item if isinstance(item, str) else item[0] for item in data]
            if len(out) != len(texts):
                raise ValueError("count mismatch")
            return out
        except Exception as error:  # network hiccup or rate limit: back off
            if attempt == 3:
                raise
            print(f"  retry after error: {error}")
            time.sleep(3 * (attempt + 1))


def main():
    wanted = sys.argv[1:] or list(LANGUAGES)
    unknown = [code for code in wanted if code not in LANGUAGES]
    if unknown:
        sys.exit("Unknown language code(s): " + ", ".join(unknown))
    workbook = load_workbook(workbook_path)
    sheet = workbook["界面文字"]
    header = {str(sheet.cell(1, c).value or "").split(" ")[0]: c for c in range(1, sheet.max_column + 1)}
    for code in LANGUAGES:
        if code not in header:
            column = max([FIRST_LANGUAGE_COLUMN - 1] + [c for c in header.values()]) + 1
            sheet.cell(1, column, f"{code} {LANGUAGES[code][0]} (machine translation)")
            header[code] = column
    rows = [r for r in range(2, sheet.max_row + 1) if sheet.cell(r, 3).value]
    for code in wanted:
        column, target = header[code], LANGUAGES[code][1]
        todo = [r for r in rows if not sheet.cell(r, column).value]
        print(f"{code}: {len(todo)} strings to translate")
        batch, size = [], 0
        def flush():
            nonlocal batch, size
            if not batch:
                return
            sources = [str(sheet.cell(r, 3).value) for r in batch]
            protected = [protect(s) for s in sources]
            results = translate_batch([p[0] for p in protected], target)
            for row, source, (_, tokens), result in zip(batch, sources, protected, results):
                result = keep_spacing(source, restore(result, tokens))
                if valid(source, result):
                    sheet.cell(row, column, result)
            batch, size = [], 0
            time.sleep(0.4)
        for r in todo:
            text = str(sheet.cell(r, 3).value)
            if batch and (len(batch) >= 40 or size + len(text) > 4000):
                flush()
            batch.append(r)
            size += len(text)
        flush()
        workbook.save(workbook_path)
    print("Saved", workbook_path.name)


if __name__ == "__main__":
    main()
