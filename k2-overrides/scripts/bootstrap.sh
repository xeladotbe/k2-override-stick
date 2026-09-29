#!/bin/sh
set -e

# Run from a private copy in /tmp: a shell keeps its script file open, and a
# stick with open files can't be unmounted when pulled (it then stays mounted
# as a dead device and the next plug-in comes up as sdb, unmounted). The stick
# is only read briefly (cfg sync) after this.
if [ -z "$K2_STICK_ROOT" ]; then
    src_scripts="$(cd "$(dirname "$0")" && pwd)"
    run_dir="/tmp/k2-overrides-run.$$"
    mkdir -p "$run_dir"
    cp -r "$src_scripts/." "$run_dir/"
    K2_STICK_ROOT="$(cd "$src_scripts/.." && pwd)" exec sh "$run_dir/bootstrap.sh" "$@"
fi

CONFIG_DIR="/mnt/UDISK/printer_data/config"
CUSTOM_DIR="$CONFIG_DIR/custom"
PRINTER_CFG="$CONFIG_DIR/printer.cfg"
CACHE_DIR="/mnt/UDISK/.k2-overrides"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STICK_ROOT="$K2_STICK_ROOT"

cleanup_run_dir() {
    case "$SCRIPT_DIR" in /tmp/k2-overrides-run.*) rm -rf "$SCRIPT_DIR" ;; esac
}
trap cleanup_run_dir EXIT

. "$SCRIPT_DIR/common.sh"

# One run at a time (hotplug coldplug, boot script and manual runs can overlap);
# /tmp is a tmpfs, so a stale lock can't survive a reboot.
LOCK_DIR="/tmp/k2-overrides.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    logger -t k2-overrides "bootstrap already running, skipping"
    exit 0
fi
trap 'rmdir "$LOCK_DIR"; cleanup_run_dir' EXIT

# The printer-side triggers (hotplug + boot script) live on the stick too and
# are (re)installed here when missing or outdated. A fresh or reset printer
# therefore needs just one manual bootstrap run, later updates come along.
install_printer_file() {
    src="$1"
    dst="$2"
    mode="$3"
    if cmp -s "$src" "$dst" 2>/dev/null; then
        return 1
    fi
    cp "$src" "$dst.tmp"
    chmod "$mode" "$dst.tmp"
    mv "$dst.tmp" "$dst"
    logger -t k2-overrides "Installed $dst"
}
install_printer_file "$SCRIPT_DIR/printer/hotplug.sh" /etc/hotplug.d/block/95-k2-overrides 700 || true
install_printer_file "$SCRIPT_DIR/printer/init.sh" /etc/init.d/k2-overrides 755 || true
if ! ls /etc/rc.d/S*k2-overrides >/dev/null 2>&1; then
    /etc/init.d/k2-overrides enable || logger -t k2-overrides "WARNING: could not enable the boot script"
fi

# Right after boot Klipper/Moonraker may still be starting; the restart and
# SET_OVERRIDE_ACTIVE calls below need them.
wait_klippy_settled || logger -t k2-overrides "WARNING: Klipper/Moonraker not answering, continuing anyway"

mkdir -p "$CUSTOM_DIR" "$CACHE_DIR"

# Safety copy of the pristine stock gcode_macro.cfg. It is pristine exactly
# when it has no _STOCK section of ours: the first time, and again after a
# firmware update that replaces gcode_macro.cfg but keeps /mnt/UDISK (seen
# with V1.1.7.0). Then the backup is refreshed and the migrations replayed
# (the version file survived, but our renames are gone). Restore with:
#   cp /mnt/UDISK/.k2-overrides/gcode_macro.cfg.orig /mnt/UDISK/printer_data/config/gcode_macro.cfg
GCODE_MACRO_CFG="$CONFIG_DIR/gcode_macro.cfg"
GCODE_MACRO_BACKUP="$CACHE_DIR/gcode_macro.cfg.orig"
STOCK_IS_PRISTINE=0
if [ -f "$GCODE_MACRO_CFG" ] && ! grep -q '^\[gcode_macro [A-Z0-9_]*_STOCK\]' "$GCODE_MACRO_CFG"; then
    STOCK_IS_PRISTINE=1
    cp "$GCODE_MACRO_CFG" "$GCODE_MACRO_BACKUP"
    logger -t k2-overrides "Backed up pristine gcode_macro.cfg"
fi

CHANGED=0

# Klipper merges same-named [gcode_macro X] sections across included files
# key-by-key instead of layering them (confirmed on real hardware
# 2026-09-27) -- rename_existing can't be used from a separately-included
# file to wrap another [gcode_macro]-defined macro, only genuine built-in
# commands from other extras modules. So we do the rename ourselves,
# directly in gcode_macro.cfg, exactly like rename_existing would if it
# could: this frees up the original name so our own custom/*.cfg can define
# it fresh with no merge conflict, calling the renamed original first.
rename_stock_macro() {
    name="$1"
    file="$2"

    if grep -q "^\[gcode_macro ${name}_STOCK\]" "$file" 2>/dev/null; then
        return 0  # already renamed on a previous bootstrap -- nothing to do
    fi

    line_raw=$(grep -n "^\[gcode_macro $name\]" "$file" 2>/dev/null | head -1)
    line_num="${line_raw%%:*}"

    if [ -z "$line_num" ]; then
        logger -t k2-overrides "WARNING: [gcode_macro $name] not found in $file -- can't rename, override for $name won't take effect"
        return 1
    fi

    head -n $((line_num - 1)) "$file" > "$file.tmp"
    echo "[gcode_macro ${name}_STOCK]" >> "$file.tmp"
    tail -n "+$((line_num + 1))" "$file" >> "$file.tmp"
    mv "$file.tmp" "$file"
    logger -t k2-overrides "Renamed [gcode_macro $name] to ${name}_STOCK in $(basename "$file")"
    CHANGED=1
}

# Structural changes to the stock gcode_macro.cfg (renames, etc.) are
# tracked as numbered, ordered migrations instead of just being run
# unconditionally on every bootstrap. This isn't needed for idempotency --
# rename_stock_macro already self-checks via the _STOCK marker -- it's so a
# stick that's already deployed and later updated to a newer version of this
# repo has a defined, ordered list of "what's new since your version" to
# apply, instead of relying on every future structural change staying
# independently self-idempotent forever. The version file only ever moves
# forward; a stick that predates this mechanism (no version file yet) starts
# at 0 and replays every migration from the start -- safe regardless, since
# each step is still idempotent via rename_stock_macro's own check.
MIGRATIONS_VERSION_FILE="$CACHE_DIR/version"
CURRENT_VERSION=$(cat "$MIGRATIONS_VERSION_FILE" 2>/dev/null || echo 0)
CURRENT_VERSION=${CURRENT_VERSION:-0}
if [ "$STOCK_IS_PRISTINE" = "1" ] && [ "$CURRENT_VERSION" != "0" ]; then
    logger -t k2-overrides "gcode_macro.cfg is stock again (firmware update?), replaying migrations"
    CURRENT_VERSION=0
fi
LATEST_VERSION=1

migration_1() {
    # Free up the stock macros our custom/*.cfg redefine (see rename_stock_macro).
    # CANCEL_PRINT and RESUME can't be renamed (they carry their own
    # rename_existing), so END_PRINT and RESUME_EXTERNAL_PROCESS, which they
    # call, are hooked instead (docs/DESIGN.md).
    rename_stock_macro START_PRINT "$GCODE_MACRO_CFG"
    rename_stock_macro PRINT_PREPARE_CLEAR "$GCODE_MACRO_CFG"
    rename_stock_macro BED_MESH_CALIBRATE_START_PRINT "$GCODE_MACRO_CFG"
    rename_stock_macro END_PRINT "$GCODE_MACRO_CFG"
    rename_stock_macro RESUME_EXTERNAL_PROCESS "$GCODE_MACRO_CFG"
    rename_stock_macro PRINT_TEMP_SET "$GCODE_MACRO_CFG"
}

v=$((CURRENT_VERSION + 1))
while [ "$v" -le "$LATEST_VERSION" ]; do
    "migration_$v"
    echo "$v" > "$MIGRATIONS_VERSION_FILE"
    logger -t k2-overrides "Applied migration $v"
    v=$((v + 1))
done

if sync_cfg_files "$STICK_ROOT" "$CUSTOM_DIR" "Copied"; then
    CHANGED=1
fi

# A .cfg that an earlier bootstrap installed but that is gone from the stick
# (renamed/retired) would otherwise stay included forever, stale macros and
# all. The manifest lists what we installed, so files someone else put into
# custom/ are never touched.
MANIFEST="$CACHE_DIR/installed.list"
PREVIOUS=$(cat "$MANIFEST" 2>/dev/null || true)
for name in $PREVIOUS; do
    if [ -f "$STICK_ROOT/$name" ]; then
        continue
    fi
    pattern="^[[:space:]]*\[include custom/$(echo "$name" | sed 's/\./\\./g')\]"
    if grep -q "$pattern" "$PRINTER_CFG" 2>/dev/null; then
        grep -v "$pattern" "$PRINTER_CFG" > "$PRINTER_CFG.tmp3" || true
        mv "$PRINTER_CFG.tmp3" "$PRINTER_CFG"
        CHANGED=1
        logger -t k2-overrides "Removed include of retired $name"
    fi
    if [ -f "$CUSTOM_DIR/$name" ]; then
        rm -f "$CUSTOM_DIR/$name"
        CHANGED=1
        logger -t k2-overrides "Removed retired custom/$name"
    fi
done
for f in "$STICK_ROOT"/*.cfg; do
    basename "$f"
done > "$MANIFEST"

# One literal include per file: a wildcard [include custom/*.cfg] breaks every
# SAVE_CONFIG (docs/DESIGN.md).
NEEDED_INCLUDES=""
for f in "$STICK_ROOT"/*.cfg; do
    name=$(basename "$f")
    if ! grep -q "^[ 	]*\[include custom/$name\]" "$PRINTER_CFG" 2>/dev/null; then
        NEEDED_INCLUDES="${NEEDED_INCLUDES}[include custom/$name]
"
    fi
done

if [ -n "$NEEDED_INCLUDES" ]; then
    # Klipper appends an auto-generated "#*# <---- SAVE_CONFIG ---->" trailer
    # after every SAVE_CONFIG, and nothing may follow it in the file, or
    # Klipper fails to parse/persist that block correctly. A blind append
    # breaks this the moment such a trailer already exists -- insert before
    # it instead.
    marker_line_raw=$(grep -n '^#\*# <---.*SAVE_CONFIG' "$PRINTER_CFG" 2>/dev/null | head -1)
    marker_line="${marker_line_raw%%:*}"

    if [ -n "$marker_line" ]; then
        insert_at=$((marker_line - 1))
        head -n "$insert_at" "$PRINTER_CFG" > "$PRINTER_CFG.tmp"
        printf '\n%s\n' "$NEEDED_INCLUDES" >> "$PRINTER_CFG.tmp"
        tail -n "+$marker_line" "$PRINTER_CFG" >> "$PRINTER_CFG.tmp"
        mv "$PRINTER_CFG.tmp" "$PRINTER_CFG"
    else
        printf '\n%s\n' "$NEEDED_INCLUDES" >> "$PRINTER_CFG"
    fi

    CHANGED=1
    logger -t k2-overrides "Added includes for custom/*.cfg"
fi

# Cache teardown.sh (and its common.sh dependency) locally -- the stick is
# no longer mounted when it's removed.
cp "$SCRIPT_DIR/teardown.sh" "$CACHE_DIR/teardown.sh"
cp "$SCRIPT_DIR/common.sh" "$CACHE_DIR/common.sh"
chmod +x "$CACHE_DIR/teardown.sh"

if [ "$CHANGED" = "1" ]; then
    logger -t k2-overrides "Config changed, triggering firmware restart"
    http_post "/printer/firmware_restart" "{}"
    sleep 3
    if ! wait_klippy_ready; then
        msg=$(http_get "/printer/info" | grep -o '"state_message": *"[^"]*"' | head -1)
        logger -t k2-overrides "WARNING: Klipper not ready after restart: ${msg:-no answer}"
        exit 1
    fi
fi

gcode_call "SET_OVERRIDE_ACTIVE VALUE=1"
logger -t k2-overrides "Overrides active"
