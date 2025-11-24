#!/bin/zsh
set -euo pipefail

python3 <<'PY'
import datetime, ipaddress, json, pathlib, plistlib, re, subprocess

log_path = pathlib.Path("/Library/Logs/Contoso/GetMonitorInfo/monitor-info.log")
now = datetime.datetime.utcnow()
timestamp = now.replace(microsecond=0).isoformat() + "Z"

def detect_location() -> str:
    try:
        output = subprocess.check_output(["ifconfig"], text=True)
    except Exception:
        return "office"

    matches = re.findall(r"\binet (?!127\.)(\d+\.\d+\.\d+\.\d+)", output)
    for candidate in matches:
        try:
            ip = ipaddress.ip_address(candidate)
        except ValueError:
            continue
        if ip in ipaddress.ip_network("10.123.0.0/16"):
            return "vpn"
    return "office"

location = detect_location()

plist_bytes = subprocess.check_output(["ioreg", "-a", "-l", "-c", "IODisplayConnect"])
data = plistlib.loads(plist_bytes)

allowed_manufacturers = {"DEL", "ENC", "NEC"}
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
            manufacturer = prod.get("ManufacturerID")
            if (
                name
                and serial
                and manufacturer
                and str(manufacturer).upper() in allowed_manufacturers
            ):
                monitors.append({"product": name, "serial": str(serial)})
        children = node.get("IORegistryEntryChildren") or []
        stack.extend(children)
    elif isinstance(node, list):
        stack.extend(node)

entry = {"timestamp": timestamp, "location": location, "monitors": monitors}

print("<result>" + json.dumps(entry) + "</result>")

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
