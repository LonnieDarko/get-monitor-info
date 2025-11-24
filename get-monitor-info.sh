#!/bin/zsh
set -euo pipefail

python3 <<'PY'
import datetime, getpass, ipaddress, json, pathlib, plistlib, re, subprocess

vpn_subnet = ipaddress.ip_network("10.123.0.0/16")
manufacturer_map = {"DEL": "DELL", "ENC": "EIZO", "NEC": "NEC"}
log_path = pathlib.Path("/Library/Logs/Contoso/GetMonitorInfo/get-monitor-info.log")

def get_current_user():
    try:
        user = subprocess.check_output(["stat", "-f%Su", "/dev/console"], text=True).strip()
        if user:
            return user
        return getpass.getuser()
    except Exception:
        return None

def get_device_name():
    try:
        name = subprocess.check_output(["scutil", "--get", "ComputerName"], text=True)
        name = name.strip()
        return name or None
    except Exception:
        return None

def get_location() -> str:
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
        if ip in vpn_subnet:
            return "vpn"
    return "office"

def parse_ts(ts: str):
    try:
        ts = ts[:-1] if ts.endswith("Z") else ts
        return datetime.datetime.fromisoformat(ts)
    except Exception:
        return None

now = datetime.datetime.utcnow()
cutoff = now - datetime.timedelta(days=30)
timestamp = now.replace(microsecond=0).isoformat() + "Z"
current_user = get_current_user()
device_name = get_device_name()
location = get_location()

plist_bytes = subprocess.check_output(["ioreg", "-a", "-l", "-c", "IODisplayConnect"])
data = plistlib.loads(plist_bytes)
monitors = []
stack = [data]
while stack:
    node = stack.pop()
    if isinstance(node, dict):
        if not node.get("IOBuiltin"):
            display_attributes = node.get("DisplayAttributes") or {}
            product_attributes = display_attributes.get("ProductAttributes") or {}
            manufacturer_id = product_attributes.get("ManufacturerID")
            manufacturer_key = str(manufacturer_id).upper() if manufacturer_id is not None else None
            product_name = product_attributes.get("ProductName")
            serial_number = product_attributes.get("SerialNumber")
            alphanumeric_serial_number = product_attributes.get("AlphanumericSerialNumber")
            has_serial = serial_number is not None or alphanumeric_serial_number is not None
            if (
                manufacturer_key in manufacturer_map
                and product_name
                and has_serial
            ):
                monitors.append(
                    {
                        "manufacturer": manufacturer_map[manufacturer_key],
                        "product_name": product_name,
                        "serial_number": str(serial_number) if serial_number is not None else None,
                        "alphanumeric_serial_number": str(alphanumeric_serial_number) if alphanumeric_serial_number is not None else None,
                    }
                )
        children = node.get("IORegistryEntryChildren") or []
        stack.extend(children)
    elif isinstance(node, list):
        stack.extend(node)

entry = {
    "timestamp": timestamp,
    "user": current_user,
    "device": device_name,
    "location": location,
    "monitors": monitors,
}

# Print for Jamf extension attribute collection
print("<result>" + json.dumps(entry) + "</result>")

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
