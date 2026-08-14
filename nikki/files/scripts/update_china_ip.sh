#!/bin/sh

. /lib/functions.sh
. "$IPKG_INSTROOT/usr/share/nikki/scripts/include.sh"

UPDATE_LOCK_DIR="$TEMP_DIR/china_ip_update.lock"
IPV4_DOWNLOAD="$TEMP_DIR/china_ip4.download.$$"
IPV6_DOWNLOAD="$TEMP_DIR/china_ip6.download.$$"
IPV4_LIST="$TEMP_DIR/china_ip4.list.$$"
IPV6_LIST="$TEMP_DIR/china_ip6.list.$$"
IPV4_CANDIDATE="$NFT_DIR/.geoip_cn.nft.new.$$"
IPV6_CANDIDATE="$NFT_DIR/.geoip6_cn.nft.new.$$"
NFT_CHECK_FILE="$TEMP_DIR/china_ip_check.nft.$$"
NFT_APPLY_FILE="$TEMP_DIR/china_ip_apply.nft.$$"

cleanup_update() {
	rm -f "$IPV4_DOWNLOAD" "$IPV6_DOWNLOAD" "$IPV4_LIST" "$IPV6_LIST" \
		"$IPV4_CANDIDATE" "$IPV6_CANDIDATE" "$NFT_CHECK_FILE" "$NFT_APPLY_FILE"
	rm -f "$UPDATE_LOCK_DIR/pid"
	rmdir "$UPDATE_LOCK_DIR" > /dev/null 2>&1
}

update_message() {
	log "China IP" "$1"
	echo "$1"
}

download_cidr_list() {
	local family url download_file list_file minimum_count count size
	family="$1"
	url="$2"
	download_file="$3"
	list_file="$4"

	case "$url" in
		https://*) ;;
		*)
			update_message "IPv${family} update URL must use HTTPS." >&2
			return 1
			;;
	esac

	if ! curl -s -f -L -m 120 --connect-timeout 15 --retry 2 \
		--proto '=https' --proto-redir '=https' --max-filesize 8388608 \
		-A 'nikki-china-ip-updater' -o "$download_file" "$url"; then
		update_message "Failed to download the China mainland IPv${family} list." >&2
		return 1
	fi
	size=$(wc -c < "$download_file")
	if [ "$size" -gt 8388608 ]; then
		update_message "The downloaded China mainland IPv${family} list is too large." >&2
		return 1
	fi

	LC_ALL=C awk -v family="$family" '
		{
			gsub(/\r/, "")
			sub(/#.*/, "")
			gsub(/^[ \t]+|[ \t]+$/, "")
			if (family == "4" && $0 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\/[0-9]+$/ && !seen[$0]++)
				print
			if (family == "6" && $0 ~ /^[0-9A-Fa-f:]+\/[0-9]+$/ && !seen[$0]++)
				print
		}
	' "$download_file" > "$list_file"

	count=$(wc -l < "$list_file")
	case "$family" in
		4) minimum_count=100 ;;
		6) minimum_count=10 ;;
	esac
	if [ "$count" -lt "$minimum_count" ]; then
		update_message "The China mainland IPv${family} list contains too few valid CIDRs ($count)." >&2
		return 1
	fi

	echo "$count"
}

generate_nft_set() {
	local family list_file output_file set_name address_type cidr
	family="$1"
	list_file="$2"
	output_file="$3"
	case "$family" in
		4)
			set_name="china_ip"
			address_type="ipv4_addr"
			;;
		6)
			set_name="china_ip6"
			address_type="ipv6_addr"
			;;
	esac

	{
		printf '%s\n\n' '#!/usr/sbin/nft -f'
		printf '%s\n' 'table inet nikki {'
		printf '\tset %s {\n' "$set_name"
		printf '\t\ttype %s\n' "$address_type"
		printf '\t\tflags interval\n'
		printf '\t\telements = {\n'
		while IFS= read -r cidr; do
			printf '\t\t\t%s,\n' "$cidr"
		done < "$list_file"
		printf '\t\t}\n'
		printf '\t}\n'
		printf '}\n'
	} > "$output_file"
	chmod 0755 "$output_file"
}

validate_nft_set() {
	local candidate check_table
	candidate="$1"
	check_table="$2"
	sed "s/table inet nikki/table inet $check_table/" "$candidate" > "$NFT_CHECK_FILE"
	nft -c -f "$NFT_CHECK_FILE" > /dev/null 2>&1
}

apply_active_sets() {
	local ipv4_changed ipv6_changed bypass_ipv4 bypass_ipv6
	ipv4_changed="$1"
	ipv6_changed="$2"

	if ! nft list table inet nikki > /dev/null 2>&1; then
		return 0
	fi

	config_load nikki
	config_get_bool bypass_ipv4 "proxy" "bypass_china_mainland_ip" 0
	config_get_bool bypass_ipv6 "proxy" "bypass_china_mainland_ip6" 0
	: > "$NFT_APPLY_FILE"
	if [ "$ipv4_changed" = 1 ] && [ "$bypass_ipv4" = 1 ]; then
		echo 'flush set inet nikki china_ip' >> "$NFT_APPLY_FILE"
		echo "include \"$GEOIP_CN_NFT\"" >> "$NFT_APPLY_FILE"
	fi
	if [ "$ipv6_changed" = 1 ] && [ "$bypass_ipv6" = 1 ]; then
		echo 'flush set inet nikki china_ip6' >> "$NFT_APPLY_FILE"
		echo "include \"$GEOIP6_CN_NFT\"" >> "$NFT_APPLY_FILE"
	fi

	if [ -s "$NFT_APPLY_FILE" ]; then
		nft -f "$NFT_APPLY_FILE"
	fi
}

prepare_files
mkdir -p "$NFT_DIR"

if ! mkdir "$UPDATE_LOCK_DIR" > /dev/null 2>&1; then
	lock_pid=$(cat "$UPDATE_LOCK_DIR/pid" 2> /dev/null)
	if [ -n "$lock_pid" ] && kill -0 "$lock_pid" > /dev/null 2>&1; then
		update_message "A China mainland IP list update is already running."
		exit 1
	fi
	rm -f "$UPDATE_LOCK_DIR/pid"
	if ! rmdir "$UPDATE_LOCK_DIR" > /dev/null 2>&1 || ! mkdir "$UPDATE_LOCK_DIR" > /dev/null 2>&1; then
		update_message "Failed to acquire the China mainland IP list update lock."
		exit 1
	fi
fi
printf '%s\n' "$$" > "$UPDATE_LOCK_DIR/pid"
trap cleanup_update EXIT
trap 'exit 1' HUP INT TERM
umask 022

config_load nikki
config_get ipv4_url "proxy" "china_ip_url" "https://ispip.clang.cn/all_cn.txt"
config_get ipv6_url "proxy" "china_ip6_url" "https://ispip.clang.cn/all_cn_ipv6.txt"

update_message "Updating China mainland IP lists."
ipv4_count=$(download_cidr_list 4 "$ipv4_url" "$IPV4_DOWNLOAD" "$IPV4_LIST") || exit 1
ipv6_count=$(download_cidr_list 6 "$ipv6_url" "$IPV6_DOWNLOAD" "$IPV6_LIST") || exit 1

generate_nft_set 4 "$IPV4_LIST" "$IPV4_CANDIDATE"
generate_nft_set 6 "$IPV6_LIST" "$IPV6_CANDIDATE"
if ! validate_nft_set "$IPV4_CANDIDATE" "nikki_geoip_check4"; then
	update_message "The downloaded China mainland IPv4 list is not valid for nftables."
	exit 1
fi
if ! validate_nft_set "$IPV6_CANDIDATE" "nikki_geoip_check6"; then
	update_message "The downloaded China mainland IPv6 list is not valid for nftables."
	exit 1
fi

ipv4_changed=0
ipv6_changed=0
if ! cmp -s "$IPV4_CANDIDATE" "$GEOIP_CN_NFT"; then
	if ! mv -f "$IPV4_CANDIDATE" "$GEOIP_CN_NFT"; then
		update_message "Failed to save the China mainland IPv4 list."
		exit 1
	fi
	ipv4_changed=1
fi
if ! cmp -s "$IPV6_CANDIDATE" "$GEOIP6_CN_NFT"; then
	if ! mv -f "$IPV6_CANDIDATE" "$GEOIP6_CN_NFT"; then
		update_message "Failed to save the China mainland IPv6 list."
		exit 1
	fi
	ipv6_changed=1
fi

if [ "$ipv4_changed" = 0 ] && [ "$ipv6_changed" = 0 ]; then
	update_message "China mainland IP lists are already up to date (IPv4: $ipv4_count, IPv6: $ipv6_count)."
	exit 0
fi

if ! apply_active_sets "$ipv4_changed" "$ipv6_changed"; then
	update_message "IP lists were saved, but applying them to the active nftables sets failed."
	exit 1
fi

update_message "China mainland IP lists updated (IPv4: $ipv4_count, IPv6: $ipv6_count)."
exit 0
