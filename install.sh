#!/bin/sh

set -eu

# Use this fork's feed setup and verify packages against the myfeed signing key.
work_dir="$(mktemp -d /tmp/nikki-install.XXXXXX)"
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
wget -O "$work_dir/feed.sh" 'https://raw.githubusercontent.com/levi882/OpenWrt-nikki/main/feed.sh'
sh "$work_dir/feed.sh"

apk add --upgrade mihomo-meta@myfeed nikki@myfeed luci-app-nikki@myfeed
if apk info --exists luci-i18n-base-zh-cn >/dev/null 2>&1; then
	apk add --upgrade luci-i18n-nikki-zh-cn@myfeed
fi

echo 'Nikki installed or updated from myfeed'
