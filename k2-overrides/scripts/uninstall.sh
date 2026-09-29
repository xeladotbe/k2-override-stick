#!/bin/sh
# Removes everything bootstrap.sh set up, cached mesh profiles included, and
# restarts Klipper. The stick can stay plugged in: the triggers go first.
#   ssh root@<printer-ip> "sh /mnt/exUDISK/k2-overrides/scripts/uninstall.sh"

# Run from a private copy in /tmp, like bootstrap.sh (keeps the stick unmountable).
if [ -z "$K2_UNINSTALL_COPY" ]; then
    run_dir="/tmp/k2-overrides-run.$$"
    mkdir -p "$run_dir"
    cp -r "$(cd "$(dirname "$0")" && pwd)/." "$run_dir/"
    K2_UNINSTALL_COPY=1 exec sh "$run_dir/uninstall.sh" "$@"
fi

CONFIG_DIR="/mnt/UDISK/printer_data/config"
CUSTOM_DIR="$CONFIG_DIR/custom"
PRINTER_CFG="$CONFIG_DIR/printer.cfg"
GCODE_MACRO_CFG="$CONFIG_DIR/gcode_macro.cfg"
CACHE_DIR="/mnt/UDISK/.k2-overrides"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

. "$SCRIPT_DIR/common.sh"

log() {
    echo "$1"
    logger -t k2-overrides "$1"
}

cleanup_run_dir() {
    case "$SCRIPT_DIR" in /tmp/k2-overrides-run.*) rm -rf "$SCRIPT_DIR" ;; esac
}
trap cleanup_run_dir EXIT

LOCK_DIR="/tmp/k2-overrides.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "The bootstrap is running right now, try again in a minute."
    exit 1
fi
trap 'rmdir "$LOCK_DIR"; cleanup_run_dir' EXIT

if print_running; then
    echo "A print is running. Uninstall after it has finished."
    exit 1
fi

# 1. Triggers, so neither a re-plug nor the next boot sets everything up again.
if [ -x /etc/init.d/k2-overrides ]; then
    /etc/init.d/k2-overrides disable 2>/dev/null || true
fi
rm -f /etc/init.d/k2-overrides /etc/hotplug.d/block/95-k2-overrides
log "Uninstall: removed the boot and hotplug scripts"

# 2. Mesh cache, while our macros are still loaded (skipped if Klipper isn't ready).
if wait_klippy_ready; then
    gcode_call "K2_CLEAR_MESH_CACHE"
    log "Uninstall: cleared the mesh cache (K2_CLEAR_MESH_CACHE)"
else
    log "Uninstall: WARNING: Klipper not ready, cached mesh profiles (bed_mesh_*) are kept"
fi

# 3. Undo the renames of the stock macros (every _STOCK section is ours).
if grep -q '^\[gcode_macro [A-Z0-9_]*_STOCK\]' "$GCODE_MACRO_CFG" 2>/dev/null; then
    sed 's/^\[gcode_macro \([A-Z0-9_]*\)_STOCK\]/[gcode_macro \1]/' "$GCODE_MACRO_CFG" > "$GCODE_MACRO_CFG.tmp"
    mv "$GCODE_MACRO_CFG.tmp" "$GCODE_MACRO_CFG"
    log "Uninstall: restored the stock macro names in gcode_macro.cfg"
fi

# 4. Our includes and files in custom/ (only what the manifest lists).
for name in $(cat "$CACHE_DIR/installed.list" 2>/dev/null); do
    pattern="^[[:space:]]*\[include custom/$(echo "$name" | sed 's/\./\\./g')\]"
    grep -v "$pattern" "$PRINTER_CFG" > "$PRINTER_CFG.tmp" || true
    mv "$PRINTER_CFG.tmp" "$PRINTER_CFG"
    rm -f "$CUSTOM_DIR/$name"
done
rm -f "$CUSTOM_DIR/.variables.cfg"
rm -rf "$CACHE_DIR"
log "Uninstall: removed the includes and config files"

# 5. Load the stock configuration.
http_post "/printer/firmware_restart" "{}"
sleep 3
if wait_klippy_ready; then
    log "Uninstall: done, the printer runs the stock configuration"
else
    msg=$(http_get "/printer/info" | grep -o '"state_message": *"[^"]*"' | head -1)
    log "Uninstall: WARNING: Klipper not ready after restart: ${msg:-no answer}"
    exit 1
fi
