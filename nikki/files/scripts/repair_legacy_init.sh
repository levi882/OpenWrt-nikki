#!/bin/sh

root="${IPKG_INSTROOT:-}"
legacy_init="$root/etc/init.d/nikki"
new_init="${legacy_init}.apk-new"
legacy_backup="$root/etc/nikki/nikki-r6-wrapper.bak"

if [ -f "$legacy_init" ] && [ -f "$new_init" ] &&
	grep -Fqx '. "$IPKG_INSTROOT/usr/share/nikki/scripts/service.sh"' "$legacy_init" &&
	! grep -Fq 'start_service()' "$legacy_init"; then
	if [ ! -e "$legacy_backup" ]; then
		cp -p "$legacy_init" "$legacy_backup" || exit 1
	fi
	mv -f "$new_init" "$legacy_init" || exit 1
	chmod 0755 "$legacy_init" || exit 1
	echo 'Repaired the legacy v1.26.2 init wrapper; its original copy is in /etc/nikki/nikki-r6-wrapper.bak.'
fi
