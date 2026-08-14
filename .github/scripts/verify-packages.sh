#!/usr/bin/env bash

set -euo pipefail

package_dir="${1:?Usage: verify-packages.sh PACKAGE_DIR}"

if [[ ! -d "$package_dir" ]]; then
	echo "::error::Package directory does not exist: $package_dir"
	exit 1
fi

luci_version="$(sed -n 's/^PKG_VERSION:=//p' luci-app-nikki/Makefile)"
nikki_version="$(sed -n 's/^PKG_VERSION:=//p' nikki/Makefile)"
nikki_release="$(sed -n 's/^PKG_RELEASE:=//p' nikki/Makefile)"

require_one_apk() {
	local package_name="$1"
	local pattern="$2"
	local matches=()

	while IFS= read -r match; do
		matches+=("$match")
	done < <(compgen -G "$package_dir/$pattern" || true)

	if (( ${#matches[@]} != 1 )); then
		echo "::error::Expected exactly one $package_name APK matching $pattern, found ${#matches[@]}."
		find "$package_dir" -maxdepth 1 -type f -printf '%f\n' | sort
		exit 1
	fi

	printf 'Verified %s: %s\n' "$package_name" "${matches[0]}"
}

require_one_apk "luci-app-nikki" "luci-app-nikki-${luci_version}-r*.apk"
require_one_apk "nikki" "nikki-${nikki_version}-r${nikki_release}.apk"
require_one_apk "mihomo-meta" "mihomo-meta-*.apk"

if compgen -G "$package_dir/mihomo-alpha-*.apk" > /dev/null; then
	echo "::error::mihomo-alpha must not be included in this release."
	exit 1
fi
