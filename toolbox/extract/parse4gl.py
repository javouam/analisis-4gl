#!/usr/bin/env python3
"""Parser compartido de fuentes Informix 4GL para los extractores del toolbox.

Convenciones (ver AGENTS.md §2):
- Encoding ISO-8859-1/CRLF: leer SIEMPRE latin-1 con errors=replace.
- Comentarios: línea que empieza (tras blancos) con '#'.
- Estructura: MAIN / FUNCTION nombre(args) / REPORT nombre(args) por programa.
- GLOBALS "archivo.4gl" = include de módulo compartido.
- DATABASE <nombre> conmuta de BD (sin credenciales en el fuente).
- CALL <fn>(...) invoca función; PREPARE/EXECUTE con EXECUTE PROCEDURE llama SPs.
"""
import os
import re

RE_FUNCTION = re.compile(r"^\s*FUNCTION\s+([A-Za-z_]\w*)\s*\(", re.I)
RE_REPORT = re.compile(r"^\s*REPORT\s+([A-Za-z_]\w*)\s*\(", re.I)
RE_MAIN = re.compile(r"^\s*MAIN\b", re.I)
RE_DATABASE = re.compile(r"^\s*DATABASE\s+([A-Za-z_]\w*)", re.I)
RE_GLOBALS_INC = re.compile(r"^\s*GLOBALS\s+\"([^\"]+)\"", re.I)
RE_MENU = re.compile(r"^\s*MENU\s+\"([^\"]*)\"", re.I)
RE_COMMAND = re.compile(r"^\s*COMMAND\s+(?:KEY\s+\(\s*\w+\s*\)\s*)?\"([^\"]*)\"(?:\s+\"([^\"]*)\")?", re.I)
RE_PROMPT = re.compile(r"\bPROMPT\b", re.I)
RE_CALL = re.compile(r"\bCALL\s+([A-Za-z_]\w*)\s*\(", re.I)
RE_RUN = re.compile(r"^\s*RUN\s+(.+)$", re.I)
RE_EXECPROC = re.compile(r"EXECUTE\s+PROCEDURE\s+(?:\w+:)?([A-Za-z_]\w*)", re.I)
RE_PREPARE_FROM = re.compile(r"PREPARE\s+\w+\s+FROM\s+(\w+)", re.I)
RE_STARTLOG = re.compile(r"\bSTARTLOG\s*\(\s*[\"']([^\"']+)[\"']", re.I)
# Complejidad (proxy cyclomatic): puntos de decisión 4GL
RE_DECISION = re.compile(r"\b(IF|CASE|WHEN|WHILE|FOR|CONSTRUCT|INPUT)\b", re.I)


def is_comment(line):
    return line.lstrip().startswith("#")


def code_lines(lines):
    return [ln for ln in lines if ln.strip() and not is_comment(ln)]


def read_source(path):
    with open(path, encoding="latin-1", errors="replace") as fh:
        return [ln.rstrip("\r\n") for ln in fh]


def find_sources(repo):
    """Yield (relpath, lines) de .4gl/.per bajo src/ (excluye .git)."""
    src_root = os.path.join(repo, "src")
    if not os.path.isdir(src_root):
        return
    for dirpath, _dirs, files in os.walk(src_root):
        if ".git" in dirpath.split(os.sep):
            continue
        for name in sorted(files):
            if name.lower().endswith((".4gl", ".per")):
                full = os.path.join(dirpath, name)
                yield os.path.relpath(full, repo), read_source(full)


def parse_program(relpath, lines):
    """Estructura de un programa .4gl (o form .per sin bloques de código)."""
    prog = {
        "file": relpath,
        "functions": [],       # [(name, line)]
        "reports": [],         # [(name, line)]
        "has_main": False,
        "databases": [],       # [(name, line)]
        "includes": [],        # [(file, line)]
        "menus": [],           # [(title, line)]
        "commands": [],        # [(menu_title, label, help, line)]
        "prompts": 0,
        "calls": [],           # [(fn, line)]
        "runs": [],            # [(cmd, line)]
        "procedures": [],      # [(sp, line)]
        "startlog": [],        # [(path, line)]
        "decision_count": 0,
        "loc": 0,
        "ncloc": 0,
    }
    current_menu = None
    for i, ln in enumerate(lines, 1):
        if not is_comment(ln):
            prog["ncloc"] += 1 if ln.strip() else 0
        prog["loc"] += 1
        if is_comment(ln):
            continue
        prog["decision_count"] += len(RE_DECISION.findall(ln))
        m = RE_MAIN.search(ln)
        if m:
            prog["has_main"] = True
            continue
        m = RE_FUNCTION.search(ln)
        if m:
            prog["functions"].append((m.group(1), i))
            continue
        m = RE_REPORT.search(ln)
        if m:
            prog["reports"].append((m.group(1), i))
            continue
        m = RE_DATABASE.search(ln)
        if m:
            prog["databases"].append((m.group(1), i))
        m = RE_GLOBALS_INC.search(ln)
        if m:
            prog["includes"].append((m.group(1), i))
        m = RE_MENU.search(ln)
        if m:
            current_menu = m.group(1)
            prog["menus"].append((current_menu, i))
        m = RE_COMMAND.search(ln)
        if m and current_menu is not None:
            prog["commands"].append((current_menu, m.group(1), m.group(2) or "", i))
        if RE_PROMPT.search(ln):
            prog["prompts"] += 1
        for m in RE_CALL.finditer(ln):
            prog["calls"].append((m.group(1), i))
        m = RE_RUN.search(ln)
        if m:
            prog["runs"].append((m.group(1).strip(), i))
        for m in RE_EXECPROC.finditer(ln):
            prog["procedures"].append((m.group(1), i))
        m = RE_STARTLOG.search(ln)
        if m:
            prog["startlog"].append((m.group(1), i))
    return prog


def ev(file, line=None):
    e = {"file": file}
    if line is not None:
        e["line"] = line
    return e
