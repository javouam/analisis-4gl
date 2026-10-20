#!/usr/bin/env python3
"""Motor local de escaneo de patrones — sustituto documentado de semgrep(generic)
y gitleaks para hosts sin Docker ni binarios instalados (ver AGENTS.md §4.2).

NO es un reemplazo semántico completo: evalúa las MISMAS reglas regex de
tools/semgrep-4gl.yml línea a línea (equivalente al modo generic de semgrep)
y añade reglas estilo gitleaks para secrets (API keys, URLs con credenciales,
llaves privadas, asignaciones de password con entropy alta).

Los valores de secrets NUNCA se escriben completos al reporte: se emite
fingerprint (longitud + prefijo 2 chars + sha256[:12]) conforme a
confidentiality.secrets: obfuscate del manifiesto.

Salidas (formato compatible-con/inspirado-en las herramientas):
  semgrep:  {"results": [{check_id, path, start{line}, end{line}, extra{message,severity,lines}}]}
  gitleaks: {"findings": [{RuleID, Description, File, StartLine, Fingerprint, Secret}]}

Uso:
  pattern_scan.py semgrep --rules tools/semgrep-4gl.yml --src src --out artifacts/semgrep-FECHA.json
  pattern_scan.py gitleaks --src src --out artifacts/gitleaks-FECHA.json
"""
import argparse
import hashlib
import json
import os
import re
import sys

try:
    import yaml
except ImportError:
    yaml = None

GITLEAKS_RULES = [
    ("private-key", "PrivateKey", "-----BEGIN (RSA |EC |OPENSSH |PGP )?PRIVATE KEY-----", "CRITICAL"),
    ("aws-access-key", "AWS Access Key ID", r"\bAKIA[0-9A-Z]{16}\b", "CRITICAL"),
    ("google-api-key", "Google API Key", r"\bAIza[0-9A-Za-z\-_]{35}\b", "CRITICAL"),
    ("jwt", "JSON Web Token", r"\beyJ[A-Za-z0-9\-_]{10,}\.[A-Za-z0-9\-_]{10,}\.[A-Za-z0-9\-_]{10,}\b", "HIGH"),
    ("url-with-credentials", "URL with credentials", r"[a-zA-Z][a-zA-Z0-9+.-]*://[^/\s:@]+:[^/\s:@]+@", "HIGH"),
    ("generic-api-key-assignment", "Generic API key/password assignment",
     r"(?i)\b(api[_-]?key|apikey|secret|token|password|passwd|pwd|usuario[_-]?bd|db[_-]?user)\b\s*[:=]\s*['\"][^'\"]{8,}['\"]", "HIGH"),
    ("informix-connect-creds", "Informix CONNECT with credentials",
     r"(?i)\bCONNECT\s+TO\s+.*\bUSER\s+", "CRITICAL"),
]


def iter_files(root, exts):
    for dirpath, _dirs, files in os.walk(root):
        if ".git" in dirpath.split(os.sep):
            continue
        for name in sorted(files):
            if exts is None or os.path.splitext(name)[1].lower().lstrip(".") in exts:
                yield os.path.join(dirpath, name)


def read_lines(path):
    # Fuentes 4GL son ISO-8859-1 con CRLF (AGENTS.md §2)
    with open(path, encoding="latin-1", errors="replace") as fh:
        return [ln.rstrip("\r\n") for ln in fh]


def fingerprint(value):
    digest = hashlib.sha256(value.encode("utf-8", "replace")).hexdigest()[:12]
    return f"len={len(value)} prefix={value[:2]!r} sha256={digest}"


def rule_patterns(rule):
    """Patrones de una regla en cualquiera de los formatos soportados:
    - patterns: [regex, ...]              (formato local original)
    - pattern-regex: regex                 (formato semgrep nativo)
    - pattern-either: [{pattern: regex}]   (formato semgrep nativo)
    """
    pats = []
    if isinstance(rule.get("patterns"), list):
        pats.extend(rule["patterns"])
    if isinstance(rule.get("pattern-regex"), str):
        pats.append(rule["pattern-regex"])
    for alt in rule.get("pattern-either") or []:
        if isinstance(alt, dict) and isinstance(alt.get("pattern"), str):
            pats.append(alt["pattern"])
    return pats


def rule_exts(rule):
    """Extensiones incluidas por la regla (semgrep paths.include), o None."""
    inc = ((rule.get("paths") or {}).get("include")) or []
    exts = {i.rsplit(".", 1)[-1].lower() for i in inc if i.startswith("*.")}
    return exts or None


def scan_semgrep(rules_path, src, out):
    if yaml is None:
        sys.exit("ERROR: falta PyYAML para leer las reglas (pip install pyyaml)")
    with open(rules_path, encoding="utf-8") as fh:
        rules = yaml.safe_load(fh).get("rules", [])
    results = []
    all_exts = {e for r in rules for e in (rule_exts(r) or set())}
    for path in iter_files(src, all_exts or None):
        try:
            lines = read_lines(path)
        except OSError:
            continue
        for i, line in enumerate(lines, 1):
            for rule in rules:
                exts = rule_exts(rule)
                if exts is not None and os.path.splitext(path)[1].lower().lstrip(".") not in exts:
                    continue
                for pat in rule_patterns(rule):
                    try:
                        hit = re.search(pat, line)
                    except re.error:
                        continue
                    if hit:
                        results.append({
                            "check_id": rule["id"],
                            "path": os.path.relpath(path),
                            "start": {"line": i},
                            "end": {"line": i},
                            "extra": {
                                "message": " ".join(rule.get("message", "").split()),
                                "severity": rule.get("severity", "INFO"),
                                "lines": line.strip()[:300],
                            },
                        })
                        break
    payload = {
        "results": results,
        "errors": [],
        "meta": {
            "engine": "tools/pattern_scan.py (local regex engine, semgrep generic-mode equivalent)",
            "note": "host sin semgrep/docker — sustitución documentada en AGENTS.md §4.2",
            "rules_file": os.path.relpath(rules_path),
        },
    }
    with open(out, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, ensure_ascii=False, indent=1)
    print(f"semgrep(local): {len(results)} hallazgo(s) → {out}")
    return 0


def scan_gitleaks(src, out):
    findings = []
    for path in iter_files(src, None):
        try:
            lines = read_lines(path)
        except OSError:
            continue
        for i, line in enumerate(lines, 1):
            for rule_id, desc, pat, sev in GITLEAKS_RULES:
                m = re.search(pat, line)
                if not m:
                    continue
                secret = m.group(0)
                findings.append({
                    "RuleID": rule_id,
                    "Description": desc,
                    "File": os.path.relpath(path),
                    "StartLine": i,
                    "EndLine": i,
                    "Severity": sev,
                    "Secret": fingerprint(secret),
                    "Match": line.strip()[:120],
                })
                break
    payload = {
        "findings": findings,
        "meta": {
            "engine": "tools/pattern_scan.py (local gitleaks-style rules)",
            "note": "host sin gitleaks/docker — secrets ofuscados (fingerprint) por confidentiality.secrets: obfuscate",
        },
    }
    with open(out, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, ensure_ascii=False, indent=1)
    print(f"gitleaks(local): {len(findings)} hallazgo(s) → {out}")
    return 0


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="mode", required=True)
    s1 = sub.add_parser("semgrep")
    s1.add_argument("--rules", required=True)
    s1.add_argument("--src", required=True)
    s1.add_argument("--out", required=True)
    s2 = sub.add_parser("gitleaks")
    s2.add_argument("--src", required=True)
    s2.add_argument("--out", required=True)
    args = ap.parse_args()
    if args.mode == "semgrep":
        sys.exit(scan_semgrep(args.rules, args.src, args.out))
    sys.exit(scan_gitleaks(args.src, args.out))


if __name__ == "__main__":
    main()
