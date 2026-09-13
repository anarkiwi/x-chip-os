#!/bin/sh -e
# Runs inside the container (as root, via `docker run`). abuild refuses to run
# as root, so this copies the build inputs into a scratch tree owned by the
# unprivileged 'build' user (created in Dockerfile), builds there, then copies
# the resulting .apk back to ./out/ (bind-mounted -- lands on the host) owned
# by HOST_UID/HOST_GID so it's not root-owned on the host afterwards.

HERE=$PWD
WORK=/home/build/work
OUT="$HERE/out"

rm -rf "$WORK" "$OUT"
mkdir -p "$WORK" "$OUT"
cp APKBUILD nand.cfg *.patch "$WORK"/
chown -R build:abuild "$WORK"

# -n: non-interactive (no prompts). No -i (install pubkey into /etc/apk/keys):
# that needs root and abuild-keygen escalates via doas, which isn't installed.
# Instead we copy the pubkey in ourselves, as root, right after -- abuild's
# own final step builds a local repository index over the packages it just
# built, and (independent of anything published or trusted elsewhere) checks
# the package it just signed against /etc/apk/keys, so the key still needs to
# be there for that self-check even though we never use this repo/index for
# anything (the .apk is installed straight from the file later with
# `apk add --allow-untrusted`).
su build -c "cd '$WORK' && abuild-keygen -a -n"
cp /home/build/.abuild/*.rsa.pub /etc/apk/keys/
su build -c "cd '$WORK' && abuild checksum"
su build -c "cd '$WORK' && abuild"

# abuild's default output isn't under $WORK at all: REPODEST defaults to
# $HOME/packages, and $repo is derived from the *parent* dir of $WORK (i.e.
# basename of /home/build -> "build"), landing at
# /home/build/packages/build/armv7/*.apk. Search all of /home/build rather
# than guess the exact layout again.
find /home/build -name '*.apk' -exec cp {} "$OUT"/ \;
chown -R "${HOST_UID:-0}:${HOST_GID:-0}" "$OUT"

ls -la "$OUT"
