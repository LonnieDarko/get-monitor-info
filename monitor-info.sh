#!/bin/zsh --no-rcs

LOG_ROOT="${HOME}/Library/Logs"
LOG_DIR="${LOG_ROOT}/Contoso/MonitorInfo"
LOG_FILE="${LOG_DIR}/monitor-info.log"

[[ -d "${LOG_DIR}" ]] || mkdir -p "${LOG_DIR}"

timestamp="$(date -u +"%Y-%m-%dT%H:%M:%S")+00:00"
user="$(stat -f '%Su' /dev/console 2>/dev/null)"
device="$(scutil --get ComputerName 2>/dev/null)"

{
  printf '<?xml version="1.0" encoding="UTF-8"?>\n'
  printf '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
  printf '<plist version="1.0">\n<dict>\n'

  ioreg -a -k DisplayAttributes |
    awk '
      /<key>ProductAttributes<\/key>/ {
          ++cnt
          sub(/ProductAttributes/, "ProductAttributes" cnt)
      }
      { print }
    ' |
    sed -n '/<key>ProductAttributes[0-9]*<\/key>/,/<\/dict>/p'

  printf '</dict>\n</plist>\n'
} |
plutil -convert json -o - - |
jq -c \
  --argjson map '{"DEL":"DELL","ENC":"EIZO","NEC":"NEC"}' \
  --arg timestamp   "$timestamp" \
  --arg user "$user" \
  --arg device  "$device" '
  {
    timestamp: $timestamp,
    user:      $user,
    device:    $device,

    monitors: (
      [ .. | objects
        | select(has("ManufacturerID"))
        | select($map[.ManufacturerID] != null)
        | {
            manufacturer: $map[.ManufacturerID],
            product: .ProductName,
            serial_number:
              (if .SerialNumber == null
               then null
               else (.SerialNumber | tostring)
               end),
            alphanumeric_serial_number: .AlphanumericSerialNumber
          }
      ]
    )
  }
' |
tee -a "${LOG_FILE}"
