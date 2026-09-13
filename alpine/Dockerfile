# Build container for the alpine flavor. Runs natively as armv7 under qemu
# (same --platform linux/arm/v7 + binfmt setup the live-build flavors use), so
# `apk --root` populates a rootfs of the same arch as the container itself --
# no cross/foreign-bootstrap handling needed. u-boot-tools provides mkimage,
# used to build /boot/boot.scr the same way flash-kernel does for the Debian
# flavors.
FROM alpine:3.24

RUN apk add --no-cache tar u-boot-tools
