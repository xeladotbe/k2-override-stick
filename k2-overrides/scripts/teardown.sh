#!/bin/sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

. "$SCRIPT_DIR/common.sh"

wait_klippy_settled || true
gcode_call "SET_OVERRIDE_ACTIVE VALUE=0"
logger -t k2-overrides "Overrides deactivated (stick removed)"
