#!/bin/sh
# Any USB disk (sda, sdb, ...): a stick that wasn't cleanly unmounted can come back as sdb.
case "$DEVNAME" in
    sd*) ;;
    *) exit 0 ;;
esac

CACHE_TEARDOWN="/mnt/UDISK/.k2-overrides/teardown.sh"

if [ "$ACTION" = "add" ]; then
    for i in 1 2 3 4 5; do
        mount | grep -q "/mnt/exUDISK" && break
        sleep 1
    done
    STICK_ROOT="/mnt/exUDISK/k2-overrides"
    if [ -d "$STICK_ROOT" ]; then
        logger -t k2-overrides "Stick detected, applying overrides"
        # Background: at boot this can wait for Klipper, and must not block the hotplug handler.
        sh "$STICK_ROOT/scripts/bootstrap.sh" >/dev/null 2>&1 &
    fi
elif [ "$ACTION" = "remove" ]; then
    if [ -x "$CACHE_TEARDOWN" ]; then
        logger -t k2-overrides "Stick removed, deactivating overrides"
        sh "$CACHE_TEARDOWN" >/dev/null 2>&1 &
    fi
fi
