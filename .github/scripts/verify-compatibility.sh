#!/usr/bin/env bash

set -euo pipefail

fail() {
	echo "::error::$*"
	exit 1
}

require_literal() {
	local file="$1"
	local literal="$2"
	grep -Fq -- "$literal" "$file" || fail "$file must contain: $literal"
}

if grep -RFn --exclude='repair_legacy_init.sh' -- '/usr/share/nikki' nikki/files luci-app-nikki/root/usr/share/rpcd/ucode/luci.nikki; then
	fail 'Runtime files must keep the v1.26.1 /etc/nikki paths for downgrade compatibility.'
fi
if grep -Fq -- '$(1)/usr/share/nikki' nikki/Makefile; then
	fail 'The package must not install a new /usr/share/nikki runtime tree.'
fi

test ! -e nikki/files/nikki-wrapper.init || fail 'The split init wrapper is not downgrade compatible.'

require_literal nikki/Makefile '+mihomo-meta'
require_literal nikki/Makefile 'PKG_RELEASE:=7'
require_literal luci-app-nikki/Makefile 'PKG_RELEASE:=2'

require_literal nikki/Makefile '$(INSTALL_BIN) $(CURDIR)/files/nikki.init $(1)/etc/init.d/nikki'
require_literal nikki/Makefile '$(INSTALL_BIN) $(CURDIR)/files/scripts/include.sh $(1)/etc/nikki/scripts/include.sh'
require_literal nikki/Makefile '$(INSTALL_BIN) $(CURDIR)/files/ucode/include.uc $(1)/etc/nikki/ucode/include.uc'
require_literal nikki/Makefile '/etc/nikki/nftables/geoip_cn.nft'
require_literal nikki/Makefile '/etc/nikki/nftables/geoip6_cn.nft'
require_literal nikki/Makefile '/etc/nikki/scripts/repair_legacy_init.sh'
require_literal nikki/files/scripts/repair_legacy_init.sh 'nikki-r6-wrapper.bak'
require_literal nikki/files/scripts/repair_legacy_init.sh '/usr/share/nikki/scripts/service.sh'
require_literal nikki/files/nikki.init '. "$IPKG_INSTROOT/etc/nikki/scripts/include.sh"'
require_literal nikki/files/scripts/update_china_ip.sh '. "$IPKG_INSTROOT/etc/nikki/scripts/include.sh"'
require_literal luci-app-nikki/root/usr/share/rpcd/ucode/luci.nikki "from '/etc/nikki/ucode/include.uc'"
require_literal .github/workflows/build-packages.yml 'PACKAGES: luci-app-nikki'
require_literal .github/workflows/release-packages.yml 'PACKAGES: luci-app-nikki'

find nikki/files -type f \( -name '*.sh' -o -name '*.init' \) -print0 |
	while IFS= read -r -d '' script; do
		sh -n "$script" || fail "Shell syntax check failed: $script"
	done

echo 'Verified legacy paths, original meta core dependency, preserved data files, and shell syntax.'
