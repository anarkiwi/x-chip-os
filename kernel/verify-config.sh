#!/bin/bash
# Verify that every CONFIG_* line in nand.cfg actually survived kconfig
# resolution in the built kernel apk.
#
# WHY THIS EXISTS: nand.cfg is a config *fragment* merged onto sunxi_defconfig
# and run through `olddefconfig`. kconfig will SILENTLY DROP or DEMOTE any
# value whose dependencies aren't met (a built-in `=y` that depends on a `=m`
# gets rewritten to `=m`; a symbol nested inside an unset `menuconfig` gate
# vanishes entirely, not even "is not set") -- with no build error. This is
# the Alpine counterpart of x-chip-deb-repo/packages/x-chip-linux-deb/
# verify-config.sh; see that repo's history for real examples this class of
# bug has caused (a kernel shipped with DIP display bridges silently as
# modules, and CONFIG_RTL8723BS was found MISSING entirely here during
# initial bring-up because CONFIG_WLAN's enclosing menuconfig gate was off).
#
# Does NOT rebuild anything -- checks the /boot/config-* file already inside
# a built .apk (or any resolved .config you point it at).
#
# Usage:
#   ./verify-config.sh                  # auto-find the newest out/linux-chip-*.apk
#   ./verify-config.sh path/to/.config  # check a specific resolved config
#
# Exit status: 0 = every nand.cfg symbol took effect; 1 = at least one was
# dropped/demoted (details printed); 2 = couldn't find a config to check.

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
FRAG="${HERE}/nand.cfg"

resolved="${1:-}"
tmp=""
if [ -z "${resolved}" ]; then
	apk="$(ls -t "${HERE}"/out/linux-chip-*.apk 2>/dev/null | head -1)"
	if [ -z "${apk}" ]; then
		echo "error: no out/linux-chip-*.apk found. Build first (\`make\`) or pass a .config path." >&2
		exit 2
	fi
	tmp="$(mktemp -d)"
	# .apk is a concatenation of gzip members (sig/control/data); tar's gzip
	# reader transparently decompresses through all of them, same as `apk`
	# itself does to read package contents.
	tar -xzf "${apk}" -C "${tmp}" boot 2>/dev/null
	resolved="$(ls "${tmp}"/boot/config-* 2>/dev/null | head -1)"
fi
if [ -z "${resolved}" ] || [ ! -f "${resolved}" ]; then
	echo "error: no resolved .config found in the apk." >&2
	[ -n "${tmp}" ] && rm -rf "${tmp}"
	exit 2
fi

echo "fragment: ${FRAG}"
echo "resolved: ${resolved}"
echo

fail=0
while IFS= read -r line; do
	if [[ "${line}" =~ ^(CONFIG_[A-Za-z0-9_]+)=(.*)$ ]]; then
		sym="${BASH_REMATCH[1]}"; want="${BASH_REMATCH[2]}"
	elif [[ "${line}" =~ ^#\ (CONFIG_[A-Za-z0-9_]+)\ is\ not\ set$ ]]; then
		sym="${BASH_REMATCH[1]}"; want="n"
	else
		continue
	fi

	if grep -q "^${sym}=" "${resolved}"; then
		got="$(sed -n "s/^${sym}=//p" "${resolved}")"
	elif grep -q "^# ${sym} is not set$" "${resolved}"; then
		got="n"
	else
		got="(absent)"
	fi

	if [ "${got}" = "${want}" ]; then
		printf '  ok    %-32s %s\n' "${sym}" "${want}"
	else
		printf '  FAIL  %-32s requested=%-6s resolved=%s\n' "${sym}" "${want}" "${got}"
		fail=1
	fi
done < "${FRAG}"

[ -n "${tmp}" ] && rm -rf "${tmp}"

echo
if [ "${fail}" -eq 0 ]; then
	echo "PASS: every nand.cfg symbol survived kconfig resolution."
else
	echo "DEMOTED/DROPPED symbols above did NOT take effect in the build."
	echo "Usually a missing dependency, or a symbol nested inside an unset menuconfig gate."
fi
exit "${fail}"
