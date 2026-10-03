#!/usr/bin/env bash

set -euo pipefail

work_dir="$(mktemp -d /tmp/nikki-cron-refresh.XXXXXX)"
trap 'rm -rf -- "$work_dir"' EXIT
cron_file="$work_dir/crontab"
restart_file="$work_dir/restarts"
updater="$work_dir/update_china_ip.sh"
cron_service="$work_dir/cron-service"
source_block="$work_dir/cron-block.sh"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

printf '%s\n' '#!/bin/sh' 'exit 0' > "$updater"
chmod +x "$updater"
cat > "$cron_service" <<'EOF'
#!/bin/sh
test "$1" = restart || exit 1
printf '%s\n' restart >> "$NIKKI_TEST_RESTARTS"
EOF
chmod +x "$cron_service"
export NIKKI_TEST_RESTARTS="$restart_file"

# Execute the actual start_service cron block against isolated files.
awk '
	/^\t# cron$/ { printing = 1 }
	/^\t# set started flag$/ { printing = 0 }
	printing { print }
' nikki/files/nikki.init |
	sed -e "s|/etc/crontabs/root|$cron_file|g" \
	    -e "s|/etc/init.d/cron|$cron_service|g" > "$source_block"
test -s "$source_block" || fail 'The service cron block was not found.'

log() { :; }
apply_cron() {
	. "$source_block"
}
scheduled_restart=1
scheduled_restart_cron='0 3 * * *'
log_scheduled_clear=1
log_scheduled_clear_cron='0 4 * * *'
china_ip_auto_update=1
china_ip_update_cron='0 5 * * *'
CHINA_IP_UPDATE_SH="$updater"
unrelated='0 6 * * * /usr/bin/other-job # unrelated'
printf '%s\n' "$unrelated" '0 1 * * * stale #nikki scheduled restart' \
	'0 1 * * * stale #nikki china ip auto update' > "$cron_file"
: > "$restart_file"

apply_cron
apply_cron
test "$(grep -c '#nikki' "$cron_file")" = 3 || fail 'Repeated start duplicated Nikki schedules.'
test "$(grep -c '#nikki scheduled restart' "$cron_file")" = 1 || fail 'Restart schedule is missing or duplicated.'
test "$(grep -c '#nikki log scheduled clear' "$cron_file")" = 1 || fail 'Log schedule is missing or duplicated.'
test "$(grep -c '#nikki china ip auto update' "$cron_file")" = 1 || fail 'China IP schedule is missing or duplicated.'
grep -Fxq "$unrelated" "$cron_file" || fail 'An unrelated schedule was modified.'
test "$(wc -l < "$restart_file")" = 2 || fail 'Cron did not restart once per refresh.'

scheduled_restart=0
log_scheduled_clear=0
china_ip_auto_update=0
apply_cron
if grep -q '#nikki' "$cron_file"; then
	fail 'Disabled schedules were not removed.'
fi
grep -Fxq "$unrelated" "$cron_file" || fail 'Disabling schedules removed an unrelated job.'
test "$(wc -l < "$restart_file")" = 3 || fail 'Removing stale schedules did not reload cron.'
apply_cron
test "$(wc -l < "$restart_file")" = 3 || fail 'An unchanged cron file triggered a redundant restart.'

china_ip_auto_update=1
CHINA_IP_UPDATE_SH="$work_dir/missing-updater.sh"
apply_cron
if grep -q '#nikki' "$cron_file"; then
	fail 'A downgraded installation scheduled a missing China IP updater.'
fi
test "$(wc -l < "$restart_file")" = 3 || fail 'Missing updater caused an unnecessary cron restart.'

echo 'PASS: cron refresh preserves China IP schedules, avoids duplicates, and retains unrelated jobs.'
