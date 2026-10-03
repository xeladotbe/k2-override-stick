# Shared Moonraker HTTP helpers for bootstrap.sh/teardown.sh.
# Plain HTTP over nc, since this BusyBox has neither curl nor wget. Meant to
# be sourced (". common.sh"), not executed directly.

MOONRAKER_PORT=7125

# A timeout, so a Moonraker that never answers can't hang the scripts forever
# (only if this BusyBox nc supports -w; an unknown flag would break every call).
NC_OPTS=""
if nc --help 2>&1 | grep -q -- "-w"; then
    NC_OPTS="-w 15"
fi

http_get() {
    printf 'GET %s HTTP/1.0\r\nHost: localhost\r\nConnection: close\r\n\r\n' "$1" \
        | nc $NC_OPTS 127.0.0.1 "$MOONRAKER_PORT" 2>/dev/null
}

http_post() {
    path="$1"
    body="$2"
    printf 'POST %s HTTP/1.0\r\nHost: localhost\r\nContent-Type: application/json\r\nContent-Length: %s\r\nConnection: close\r\n\r\n%s' \
        "$path" "${#body}" "$body" | nc $NC_OPTS 127.0.0.1 "$MOONRAKER_PORT" >/dev/null 2>&1
}

gcode_call() {
    http_post "/printer/gcode/script" "{\"script\":\"$1\"}"
}

# Waits (max ~2 min) until Klipper has left its startup phase, i.e. Moonraker
# answers and the state is ready/error/shutdown. Deliberately not "ready only":
# bootstrap must still be able to run to repair a Klipper stuck in "error".
wait_klippy_settled() {
    tries=0
    while [ $tries -lt 60 ]; do
        state=$(http_get "/printer/info" | grep -o '"state": *"[a-z]*"' | head -1)
        case "$state" in
            *ready*|*error*|*shutdown*) return 0 ;;
        esac
        sleep 2
        tries=$((tries + 1))
    done
    return 1
}

# True while a print runs or is paused (our heat soak pauses it too); a Klipper
# restart would kill it.
print_running() {
    # A Klipper in shutdown/error keeps the crashed print's printing/paused, but nothing is running anymore.
    reply=$(http_get "/printer/objects/query?print_stats=state&webhooks=state")
    echo "$reply" | grep -q '"webhooks": *{ *"state": *"ready"' || return 1
    state=$(echo "$reply" | grep -o '"print_stats": *{ *"state": *"[a-z]*"')
    case "$state" in
        *printing*|*paused*) return 0 ;;
    esac
    return 1
}

# Waits (max ~1 min) until Klipper is ready, e.g. after a firmware_restart.
wait_klippy_ready() {
    tries=0
    while [ $tries -lt 30 ]; do
        echo "$(http_get "/printer/info")" | grep -q '"state": *"ready"' && return 0
        sleep 2
        tries=$((tries + 1))
    done
    return 1
}

# Copies every *.cfg from $1 (source dir) into $2 (dest dir) that differs
# (by content) from what's already there, logging each copy with the $3
# prefix. Exit status 0 if anything was copied, 1 if nothing changed --
# use in an `if sync_cfg_files ...; then` check.
sync_cfg_files() {
    src_dir="$1"
    dst_dir="$2"
    log_prefix="$3"
    changed=1

    for f in "$src_dir"/*.cfg; do
        [ -f "$f" ] || continue
        name=$(basename "$f")
        if ! cmp -s "$f" "$dst_dir/$name" 2>/dev/null; then
            cp "$f" "$dst_dir/$name"
            logger -t k2-overrides "$log_prefix: $name"
            changed=0
        fi
    done

    return "$changed"
}
