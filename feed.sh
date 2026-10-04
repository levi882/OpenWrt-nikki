#!/bin/sh

set -eu

# Signed packages published by levi882/Openwrt_packages.
if [ ! -x /usr/bin/apk ] || [ ! -x /sbin/fw4 ]; then
	echo 'This feed requires OpenWrt with apk and firewall4.' >&2
	exit 1
fi
# shellcheck source=/dev/null
. /etc/openwrt_release
case "$DISTRIB_RELEASE:$DISTRIB_ARCH" in
	*25.12*:x86_64) ;;
	*)
		echo "myfeed currently supports OpenWrt 25.12 / x86_64; got $DISTRIB_RELEASE / $DISTRIB_ARCH." >&2
		exit 1
		;;
esac

repository_url='https://openwrt-packages.pages.dev'
feed_url="$repository_url/openwrt-25.12/x86_64/myfeed"
mkdir -p /etc/apk/keys /etc/apk/repositories.d
touch /etc/apk/repositories.d/customfeeds.list
key_file="$(mktemp /tmp/nikki-myfeed-key.XXXXXX)"
repository_file="$(mktemp /etc/apk/repositories.d/.nikki-myfeed.XXXXXX)"
trap 'rm -f "$key_file" "$repository_file"' EXIT HUP INT TERM

echo 'Adding the myfeed signing key'
wget -O "$key_file" "$repository_url/public-key.pem"
test -s "$key_file"
cp "$key_file" /etc/apk/keys/myfeed.pem

# Keep unrelated feeds and make both repeated installation and @myfeed pins work.
awk -v feed="$feed_url/packages.adb" '
	index($0, "https://nikkinikki.pages.dev/") == 0 && index($0, feed) == 0 { print }
' /etc/apk/repositories.d/customfeeds.list > "$repository_file"
printf '@myfeed %s/packages.adb\n' "$feed_url" >> "$repository_file"
mv "$repository_file" /etc/apk/repositories.d/customfeeds.list

echo 'Refreshing the signed myfeed repository'
apk update
echo 'Feed configured successfully'
