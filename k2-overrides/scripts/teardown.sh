#!/bin/sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

. "$SCRIPT_DIR/common.sh"

# A USB glitch drops the stick and brings it back within seconds (remove, then
# add; seen 2026-11-01, mounted again after 11 s): only switch off if it stays
# gone. A dead mount of a pulled stick has no device node left.
sleep 15
dev=$(mount | awk '$3 == "/mnt/exUDISK" { print $1; exit }')
if [ -n "$dev" ] && [ -b "$dev" ] && [ -d /mnt/exUDISK/k2-overrides ]; then
    logger -t k2-overrides "Stick is back ($dev), overrides stay active"
    exit 0
fi

wait_klippy_settled || true
gcode_call "SET_OVERRIDE_ACTIVE VALUE=0"
logger -t k2-overrides "Overrides deactivated (stick removed)"
