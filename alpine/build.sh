#!/bin/sh -ex
# Builds the alpine-headless rootfs tar for the CHIP.
#
# Unlike the Debian flavors (live-build + debootstrap), this populates a
# rootfs directly with `apk --root`: apk doesn't need a chroot to fetch and
# unpack packages, only to run their post-install triggers -- and since this
# container already runs natively as armv7 (via qemu/binfmt, same as the
# live-build containers), those triggers run fine with a plain `chroot`.
#
# No dedicated CHIP apk repository: the kernel is built by ../kernel and
# bind-mounted in at /kernel-out, then installed straight from the .apk file
# with `apk add --allow-untrusted` (see kernel/build-apk.sh for why that's
# safe -- we never index or publish this key, so there's nothing else it
# could mistakenly trust).

ALPINE_BRANCH=v3.24
MIRROR=https://dl-cdn.alpinelinux.org/alpine
ROOTFS=/build/rootfs
OUT=/build/alpine-rootfs.tar.gz

rm -rf "$ROOTFS" "$OUT"
mkdir -p "$ROOTFS"

cat > /tmp/repositories <<EOF
$MIRROR/$ALPINE_BRANCH/main
$MIRROR/$ALPINE_BRANCH/community
EOF
# Carry the same repositories file into the image so on-device `apk
# upgrade`/`apk add` keep working. We never list a kernel package here, and
# our own linux-chip.apk isn't served by any repository (it's a bare file
# install below) -- so `apk upgrade` has nothing matching to swap it for and
# leaves it alone.
install -Dm644 /tmp/repositories "$ROOTFS"/etc/apk/repositories

# --keys-dir: a fresh --root has no trusted keys of its own yet (the
# alpine-keys package, which would normally provide them, is one of the
# things we're about to install) -- point at the build container's own
# already-trusted keys (from its alpine:3.24 base image) instead of
# disabling verification. Real Alpine keys land in the new root normally as
# part of installing alpine-base/alpine-keys.
apk add --root "$ROOTFS" --repositories-file /tmp/repositories \
    --keys-dir /etc/apk/keys \
    --update-cache --initdb \
    alpine-base openrc \
    dbus dbus-openrc \
    connman connman-openrc wpa_supplicant \
    linux-firmware-rtl_bt \
    openssh-server openssh-server-common-openrc \
    sudo nano \
    mtd-utils

# --- kernel ------------------------------------------------------------
KERNEL_APK=$(ls /kernel-out/linux-chip-*.apk 2>/dev/null | head -1)
[ -n "$KERNEL_APK" ] || { echo "no kernel apk in /kernel-out -- run 'make' in ../kernel first" >&2; exit 1; }
apk add --root "$ROOTFS" --repositories-file /tmp/repositories --allow-untrusted "$KERNEL_APK"

KVER=$(basename "$(echo "$ROOTFS"/lib/modules/*)")
[ -n "$KVER" ] && [ -d "$ROOTFS/lib/modules/$KVER" ] || { echo "couldn't determine installed kernel version" >&2; exit 1; }

# --- users / hostname ----------------------------------------------------
echo chip > "$ROOTFS"/etc/hostname
chroot "$ROOTFS" adduser -D chip
echo 'chip:chip' | chroot "$ROOTFS" chpasswd
chroot "$ROOTFS" addgroup chip wheel
# Enable the stock (commented-out) wheel-group rule rather than hand-writing
# a sudoers.d drop-in -- keeps the file diff minimal and visdoc-obvious.
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' "$ROOTFS"/etc/sudoers
# connman's own shipped D-Bus policy (/usr/share/dbus-1/system.d/connman.conf)
# already allows the "netdev" group to talk to net.connman (that's what lets
# connmanctl work un-sudo'd) -- without this, every connmanctl call gets a
# D-Bus policy rejection (found on hw 2026-09-10: "Rejected send message...").
chroot "$ROOTFS" addgroup chip netdev

# --- onboard wifi (rtw88 RTL8723BS) ----------------------------------------
# The kernel uses rtw88's RTL8723BS driver (kernel/rtw88-rtl8723bs-6.18.patch),
# not the staging r8723bs one. Its firmware, rtw88/rtw8723b_fw.bin (v41), is in
# upstream linux-firmware but newer than Alpine 3.24's linux-firmware-rtw88,
# so it's vendored here with its licence.
# TODO: once the Alpine release this tracks ships rtw8723b_fw.bin in
# linux-firmware-rtw88, install that package instead and delete firmware/.
install -Dm644 firmware/rtw88/rtw8723b_fw.bin "$ROOTFS"/lib/firmware/rtw88/rtw8723b_fw.bin
install -Dm644 firmware/LICENCE.rtlwifi_firmware.txt "$ROOTFS"/lib/firmware/LICENCE.rtlwifi_firmware.txt

# --- serial console --------------------------------------------------------
# OpenRC doesn't auto-spawn a getty from the kernel `console=` cmdline the way
# systemd does, so ttyS0 needs wiring up explicitly even though the kernel
# also has a composite-out fbcon (tty1 already has a getty by default).
sed -i '/^#ttyS0::respawn/c\ttyS0::respawn:/sbin/getty -L 115200 ttyS0 vt100' "$ROOTFS"/etc/inittab

# --- services --------------------------------------------------------------
for svc in devfs dmesg mdev hwdrivers; do chroot "$ROOTFS" rc-update add "$svc" sysinit; done
for svc in modules sysctl hostname bootmisc syslog swclock seedrng; do chroot "$ROOTFS" rc-update add "$svc" boot; done
# ntpd (busybox's, from busybox-openrc): the CHIP has no RTC, so without it
# the clock starts wherever swclock left it (1970 on a fresh flash) and every
# TLS cert -- e.g. `apk update` against dl-cdn -- reads as not trusted. It
# keeps retrying until wifi is up; swclock then carries the synced time across
# reboots.
for svc in dbus connman sshd ntpd local; do chroot "$ROOTFS" rc-update add "$svc" default; done
for svc in mount-ro killprocs savecache; do chroot "$ROOTFS" rc-update add "$svc" shutdown; done

# --- boot.scr ----------------------------------------------------------
sed "s/@@KERNEL_VERSION@@/$KVER/g" bootscr.chip.tmpl > /tmp/boot.scr.src
mkimage -A arm -T script -C none -n "CHIP boot script" -d /tmp/boot.scr.src "$ROOTFS"/boot/boot.scr

# apk's own cache/state isn't needed on-device.
rm -rf "$ROOTFS"/var/cache/apk/*

tar -C "$ROOTFS" -czf "$OUT" .
chown "${HOST_UID:-0}:${HOST_GID:-0}" "$OUT"

ls -la "$OUT"
