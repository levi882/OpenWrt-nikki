#!/usr/bin/env bash

set -euo pipefail

if (( $# != 4 )); then
	echo "Usage: $0 APK_TOOL V1_26_1_APK BROKEN_V1_26_2_APK CANDIDATE_V1_26_2_APK" >&2
	exit 2
fi

apk_tool="$(realpath "$1")"
old_apk="$(realpath "$2")"
broken_apk="$(realpath "$3")"
new_apk="$(realpath "$4")"
work_dir="$(mktemp -d /tmp/nikki-apk-roundtrip.XXXXXX)"
root_dir="$work_dir/root"
repair_root_dir="$work_dir/repair-root"
deps_apk="$work_dir/compat-deps-1.apk"

cleanup() {
	case "$work_dir" in
		/tmp/nikki-apk-roundtrip.*) rm -rf -- "$work_dir" ;;
		*) echo "Refusing to remove unexpected path: $work_dir" >&2 ;;
	esac
}
trap cleanup EXIT

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

require_marker() {
	local marker="$1"
	local file="$2"
	grep -Fq -- "$marker" "$file" || fail "$file did not preserve $marker"
}

mkdir -p "$root_dir"
"$apk_tool" mkpkg \
	-o "$deps_apk" \
	-I name:compat-deps \
	-I version:1-r1 \
	-I arch:x86_64 \
	-I description:roundtrip-test \
	-I license:MIT \
	-I 'provides:ca-bundle curl firewall4 ip-full kmod-dummy kmod-inet-diag kmod-nft-socket kmod-nft-tproxy kmod-tun libc mihomo mihomo-meta yq'

apk_add() {
	"$apk_tool" \
		--root "$root_dir" \
		--allow-untrusted \
		--no-scripts \
		--force-non-repository \
		add "$@"
}

repair_apk_add() {
	"$apk_tool" \
		--root "$repair_root_dir" \
		--allow-untrusted \
		--no-scripts \
		--force-non-repository \
		add "$@"
}

echo 'Installing official v1.26.1 baseline...'
"$apk_tool" \
	--root "$root_dir" \
	--initdb \
	--allow-untrusted \
	--no-scripts \
	--force-non-repository \
	add "$deps_apk" "$old_apk"

printf '%s\n' '# roundtrip-config-marker' >> "$root_dir/etc/config/nikki"
printf '%s\n' '# roundtrip-mixin-marker' >> "$root_dir/etc/nikki/mixin.yaml"
printf '%s\n' '# roundtrip-nft-marker' >> "$root_dir/etc/nikki/nftables/geoip_cn.nft"

echo 'Upgrading to the candidate v1.26.2 package...'
apk_add "$new_apk"

grep -Fq -- '/etc/nikki/scripts/include.sh' "$root_dir/etc/init.d/nikki" ||
	fail 'v1.26.2 init script does not use the legacy runtime path'
test -x "$root_dir/etc/nikki/scripts/include.sh" || fail 'v1.26.2 legacy include script is missing'
test -x "$root_dir/etc/nikki/scripts/update_china_ip.sh" || fail 'v1.26.2 updater is missing'
test ! -e "$root_dir/usr/share/nikki" || fail 'v1.26.2 unexpectedly installs the incompatible /usr/share/nikki tree'

require_marker roundtrip-config-marker "$root_dir/etc/config/nikki"
require_marker roundtrip-mixin-marker "$root_dir/etc/nikki/mixin.yaml"
require_marker roundtrip-nft-marker "$root_dir/etc/nikki/nftables/geoip_cn.nft"

# Simulate a protected/local init script. APK must preserve it during the
# downgrade, and the newer script must still run against v1.26.1 files.
printf '%s\n' '# roundtrip-protected-init-marker' >> "$root_dir/etc/init.d/nikki"

echo 'Downgrading back to official v1.26.1...'
apk_add "$old_apk"

require_marker roundtrip-protected-init-marker "$root_dir/etc/init.d/nikki"
require_marker roundtrip-config-marker "$root_dir/etc/config/nikki"
require_marker roundtrip-mixin-marker "$root_dir/etc/nikki/mixin.yaml"
require_marker roundtrip-nft-marker "$root_dir/etc/nikki/nftables/geoip_cn.nft"

test -x "$root_dir/etc/nikki/scripts/include.sh" || fail 'v1.26.1 include script is missing after downgrade'
test ! -e "$root_dir/usr/share/nikki" || fail 'A dangling /usr/share/nikki tree remains after downgrade'
grep -Fq -- '/etc/nikki/scripts/include.sh' "$root_dir/etc/init.d/nikki" ||
	fail 'The protected v1.26.2 init script cannot use v1.26.1 files'
sh -n "$root_dir/etc/init.d/nikki"

if (
	extra_command() { :; }
	IPKG_INSTROOT="$root_dir"
	. "$root_dir/etc/init.d/nikki"
	update_china_ip
) > "$work_dir/updater.out" 2>&1; then
	fail 'The protected init script unexpectedly ran a removed updater after downgrade'
fi
grep -Fq -- 'updater is not available' "$work_dir/updater.out" ||
	fail 'The protected init script did not fail safely when the updater was removed'

"$apk_tool" --root "$root_dir" list --installed --manifest |
	grep -Fq -- 'nikki 2026.04.08-r1' || fail 'The final installed package is not v1.26.1'

echo 'PASS: v1.26.1 -> v1.26.2 -> protected-init v1.26.1 downgrade preserved configuration and runnable paths.'

echo 'Installing the previously published v1.26.2 package...'
mkdir -p "$repair_root_dir"
"$apk_tool" \
	--root "$repair_root_dir" \
	--initdb \
	--allow-untrusted \
	--no-scripts \
	--force-non-repository \
	add "$deps_apk" "$broken_apk"

grep -Fq -- '/usr/share/nikki/scripts/service.sh' "$repair_root_dir/etc/init.d/nikki" ||
	fail 'The previous v1.26.2 fixture does not contain the incompatible init wrapper'
printf '%s\n' '# protected-r6-wrapper-marker' >> "$repair_root_dir/etc/init.d/nikki"
printf '%s\n' '# r6-upgrade-config-marker' >> "$repair_root_dir/etc/config/nikki"

echo 'Upgrading the protected legacy wrapper to the candidate package...'
repair_apk_add "$new_apk"
test -x "$repair_root_dir/etc/nikki/scripts/repair_legacy_init.sh" ||
	fail 'The candidate package does not contain the legacy init repair hook'
IPKG_INSTROOT="$repair_root_dir" "$repair_root_dir/etc/nikki/scripts/repair_legacy_init.sh"

require_marker protected-r6-wrapper-marker "$repair_root_dir/etc/nikki/nikki-r6-wrapper.bak"
require_marker r6-upgrade-config-marker "$repair_root_dir/etc/config/nikki"
grep -Fq -- '/usr/share/nikki/scripts/service.sh' "$repair_root_dir/etc/nikki/nikki-r6-wrapper.bak" ||
	fail 'The protected legacy wrapper backup is incomplete'
grep -Fq -- '/etc/nikki/scripts/include.sh' "$repair_root_dir/etc/init.d/nikki" ||
	fail 'The protected legacy wrapper was not replaced with the compatible init script'
grep -Fq -- 'start_service()' "$repair_root_dir/etc/init.d/nikki" ||
	fail 'The repaired init entry point is not the full service script'
test ! -e "$repair_root_dir/usr/share/nikki" ||
	fail 'The repaired candidate still depends on the incompatible /usr/share/nikki tree'
sh -n "$repair_root_dir/etc/init.d/nikki"

echo 'PASS: protected previous-v1.26.2 wrapper was backed up and repaired during the candidate upgrade.'
