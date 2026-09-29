#!/bin/sh /etc/rc.common
# Boot counterpart of /etc/hotplug.d/block/95-k2-overrides. Coldplug may fire
# before Klipper is up, or not at all, so once the system is up: apply the
# stick if it is there, else deactivate the overrides (stick pulled while the
# printer was off, no hotplug "remove" ran). Runs in the background.
START=99

STICK_ROOT="/mnt/exUDISK/k2-overrides"
CACHE_TEARDOWN="/mnt/UDISK/.k2-overrides/teardown.sh"

boot_apply() {
    tries=0
    while [ $tries -lt 20 ]; do
        mount | grep -q "/mnt/exUDISK" && break
        sleep 2
        tries=$((tries + 1))
    done

    if [ -d "$STICK_ROOT" ]; then
        logger -t k2-overrides "Boot: stick found, applying overrides"
        sh "$STICK_ROOT/scripts/bootstrap.sh"
    elif [ -x "$CACHE_TEARDOWN" ]; then
        logger -t k2-overrides "Boot: no stick, deactivating overrides"
        sh "$CACHE_TEARDOWN"
    fi
}

start() {
    boot_apply >/dev/null 2>&1 &
}
