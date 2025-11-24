#!/bin/zsh
set -euo pipefail

# Sammle Display-Daten als Plist, verarbeite sie in Python und logge Ergebnisse nach /Library/Logs/Contoso/GetMonitorInfo/monitor-info.log
python3 <<'PY'
import datetime, json, pathlib, plistlib, subprocess

log_path = pathlib.Path("/Library/Logs/Contoso/GetMonitorInfo/monitor-info.log")
now = datetime.datetime.utcnow()
timestamp = now.replace(microsecond=0).isoformat() + "Z"

# ioreg als Plist laden
plist_bytes = subprocess.check_output(["ioreg", "-a", "-l", "-c", "IODisplayConnect"])
data = plistlib.loads(plist_bytes)

# Displays aus dem Baum einsammeln
monitors = []
stack = [data]
while stack:
    node = stack.pop()
    if isinstance(node, dict):
        if not node.get("IOBuiltin"):
            attrs = node.get("DisplayAttributes") or {}
            prod = attrs.get("ProductAttributes") or {}
            name = prod.get("ProductName")
            serial = prod.get("AlphanumericSerialNumber")
            if name and serial:
                monitors.append({"product": name, "serial": str(serial)})
        children = node.get("IORegistryEntryChildren") or []
        stack.extend(children)
    elif isinstance(node, list):
        stack.extend(node)

entry = {"timestamp": timestamp, "monitors": monitors}

# Ausgabe für Jamf
print("<result>" + json.dumps(entry) + "</result>")

# Log als NDJSON nach /Library/Logs/Contoso/GetMonitorInfo/monitor-info.log; Einträge älter als 30 Tage entfernen
cutoff = now - datetime.timedelta(days=30)

def parse_ts(ts: str):
    try:
        ts = ts[:-1] if ts.endswith("Z") else ts
        return datetime.datetime.fromisoformat(ts)
    except Exception:
        return None

existing = []
if log_path.exists():
    with log_path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            t = parse_ts(obj.get("timestamp", ""))
            if t and t >= cutoff:
                existing.append(obj)

existing.append(entry)
log_path.parent.mkdir(parents=True, exist_ok=True)
with log_path.open("w", encoding="utf-8") as f:
    for obj in existing:
        f.write(json.dumps(obj) + "\n")
PY
