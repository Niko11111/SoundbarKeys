#!/usr/bin/env python3
"""Convention check for SoundbarKeys. Exit code 0 = all rules hold.

Run from anywhere:  python3 tools/check_conventions.py

Rules (see CONTRIBUTING.md):
  function_length     functions/methods/SwiftUI bodies max. 50 lines
  file_length         source files max. 1000 lines
  parameter_count     functions max. 5 parameters
  em_dash             no long dash (U+2014) anywhere
  ascii_umlauts       German texts use ä/ö/ü/ß, never ae/oe/ue/ss spellings
  localization        every UI string in the code has a German translation and vice versa
  python_syntax       every .py file parses
  shell_syntax        every .sh file passes `bash -n`
"""

import ast
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MAX_FUNCTION_LINES = 50
MAX_FILE_LINES = 1000
MAX_PARAMETERS = 5
EM_DASH = chr(0x2014)  # written as code point so this file does not flag itself
SKIP_DIRS = {".git", ".build", "build", ".venv", "__pycache__", "CompiledIcon"}
TEXT_SUFFIXES = {".swift", ".py", ".sh", ".md", ".strings", ".plist", ".json", ".svg"}

SWIFT_SOURCES = ROOT / "App" / "Sources"
GERMAN_STRINGS = ROOT / "App" / "Resources" / "Localization" / "de.lproj" / "Localizable.strings"

# Typical ASCII spellings of German words with umlauts (kept short to avoid false positives).
ASCII_UMLAUT_WORDS = re.compile(
    r"\b(fuer|ueber|Ueber|koennen|moechte|Lautstaerke|groesse|Groesse|schliessen|waehlen|"
    r"Schluessel|aendern|Aenderung|noetig|gueltig|Gueltig|hoechstens|zurueck|Tastendruecke)\b"
)
# SwiftUI/Foundation initializers whose first string literal is a localization key.
LOCALIZED_CALL = re.compile(
    r'(?:String\(localized: |Text\(|Button\(|Label\(|LabeledContent\(|Toggle\(|Picker\(|Section\(|TextField\(|SecureField\(|DatePicker\()'
    r'"((?:[^"\\]|\\\(.*?\))*)"'
)


def files(suffixes):
    for path in ROOT.rglob("*"):
        if path.is_file() and path.suffix in suffixes and not SKIP_DIRS.intersection(path.parts):
            yield path


def rel(path):
    return path.relative_to(ROOT)


def block_length(lines, start):
    """Lines from `start` until its braces balance again (Swift)."""
    depth = 0
    for end in range(start, len(lines)):
        depth += lines[end].count("{") - lines[end].count("}")
        if depth == 0 and end > start:
            return end - start + 1
    return len(lines) - start


def parameter_count(signature):
    """Number of parameters in a Swift parameter list; colons inside [...] or <...> types don't count."""
    flat = re.sub(r"\[[^\]]*\]|<[^>]*>", "", signature)
    return flat.count(":")


def check_swift_functions(problems):
    header = re.compile(r"\b(func|init)\b.*\{\s*$|\bvar body: some View \{\s*$")
    for path in files({".swift"}):
        lines = path.read_text().splitlines()
        for i, line in enumerate(lines):
            if not header.search(line):
                continue
            n = block_length(lines, i)
            if n > MAX_FUNCTION_LINES:
                problems.append(("function_length", f"{rel(path)}:{i + 1} {n} lines: {line.strip()[:60]}"))
            params = re.search(r"\bfunc\b[^(]*\((.*)\)", line)
            if params and parameter_count(params.group(1)) > MAX_PARAMETERS:
                problems.append(("parameter_count", f"{rel(path)}:{i + 1}: {line.strip()[:60]}"))


def check_python_functions(problems):
    for path in files({".py"}):
        try:
            tree = ast.parse(path.read_text())
        except SyntaxError as e:
            problems.append(("python_syntax", f"{rel(path)}:{e.lineno}: {e.msg}"))
            continue
        for node in ast.walk(tree):
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                n = node.end_lineno - node.lineno + 1
                if n > MAX_FUNCTION_LINES:
                    problems.append(("function_length", f"{rel(path)}:{node.lineno} {n} lines: {node.name}"))
                if len(node.args.args) > MAX_PARAMETERS:
                    problems.append(("parameter_count", f"{rel(path)}:{node.lineno}: {node.name}"))


def check_text_rules(problems):
    for path in files(TEXT_SUFFIXES):
        text = path.read_text(errors="replace")
        lines = text.splitlines()
        if path.suffix in {".swift", ".py", ".sh"} and len(lines) > MAX_FILE_LINES:
            problems.append(("file_length", f"{rel(path)}: {len(lines)} lines"))
        for i, line in enumerate(lines, 1):
            if EM_DASH in line:
                problems.append(("em_dash", f"{rel(path)}:{i}"))
            if path.suffix == ".strings" and "de.lproj" in path.parts and ASCII_UMLAUT_WORDS.search(line):
                problems.append(("ascii_umlauts", f"{rel(path)}:{i}: {ASCII_UMLAUT_WORDS.search(line).group(0)}"))


def normalize_key(key):
    """Interpolations in code and %@/%lld/%d in .strings both become one marker."""
    key = re.sub(r"\\\(.*?\)", "§", key)
    return re.sub(r"%(lld|ld|d|@)", "§", key)


def check_localization(problems):
    code = "".join(p.read_text() for p in SWIFT_SOURCES.rglob("*.swift"))
    code_keys = {normalize_key(m.group(1)) for m in LOCALIZED_CALL.finditer(code)} - {"§"}
    german = GERMAN_STRINGS.read_text()
    german_keys = {normalize_key(k) for k in re.findall(r'^"(.*?)" =', german, re.M)}
    for key in sorted(code_keys - german_keys):
        problems.append(("localization", f"missing German translation: {key}"))
    for key in sorted(german_keys - code_keys):
        problems.append(("localization", f"unused German translation: {key}"))


def check_shell_syntax(problems):
    for path in files({".sh"}):
        result = subprocess.run(["bash", "-n", str(path)], capture_output=True, text=True)
        if result.returncode != 0:
            problems.append(("shell_syntax", f"{rel(path)}: {result.stderr.strip()}"))


def main():
    problems = []
    check_swift_functions(problems)
    check_python_functions(problems)
    check_text_rules(problems)
    check_localization(problems)
    check_shell_syntax(problems)
    for rule, detail in problems:
        print(f"[{rule}] {detail}")
    print(f"{len(problems)} problem(s)" if problems else "All conventions hold.")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
