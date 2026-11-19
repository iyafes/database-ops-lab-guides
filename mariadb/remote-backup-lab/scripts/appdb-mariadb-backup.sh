#!/bin/bash
# BACKUP host. Installed as /usr/local/bin/appdb-mariadb-backup.sh (root:root, 755), run by cron.
# Pulls a dump of "appdb" from the source host over SSH, compresses it, verifies it,
# stores it atomically, then applies retention. Never prints credentials.
set -uo pipefail
umask 077

# Defaults suit the lab; every value can be overridden from the environment (used by drills).
BACKUP_DIR="${BACKUP_DIR:-/backup/mariadb}"
KEY="${KEY:-/home/backupadm/.ssh/mariadb_backup_key}"
REMOTE="${REMOTE:-backupadm@192.168.50.10}"
REMOTE_CMD="sudo /usr/local/sbin/appdb-mariadb-dump.sh"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
MIN_BYTES="${MIN_BYTES:-10240}"

LOG="$BACKUP_DIR/backup.log"
LOCK="$BACKUP_DIR/.appdb-backup.lock"
TS="$(date +%F_%H%M%S)"
FINAL="$BACKUP_DIR/appdb_${TS}.sql.gz"
TMP="$BACKUP_DIR/.appdb_${TS}.sql.gz.part"

log() { echo "$(date '+%F %T') [$$] $*" >> "$LOG"; }

# Prevent overlapping runs
exec 9>"$LOCK"
if ! flock -n 9; then
    log "ERROR: another backup is already running, exiting"
    exit 1
fi

# Remove the incomplete file on any exit (after a successful mv it no longer exists)
trap 'rm -f "$TMP"' EXIT

fail() {
    log "FAILED: $*"
    exit 1
}

log "START backup -> $FINAL"

ssh -i "$KEY" \
    -o BatchMode=yes -o ConnectTimeout=15 \
    -o ServerAliveInterval=30 -o ServerAliveCountMax=4 \
    "$REMOTE" "$REMOTE_CMD" 2>>"$LOG" | gzip -c > "$TMP"
rc=("${PIPESTATUS[@]}")

[ "${rc[0]}" -eq 0 ] || fail "ssh/dump exited with code ${rc[0]}"
[ "${rc[1]}" -eq 0 ] || fail "gzip exited with code ${rc[1]}"

gzip -t "$TMP" 2>>"$LOG" || fail "gzip integrity check failed"

SIZE="$(stat -c %s "$TMP")"
[ "$SIZE" -ge "$MIN_BYTES" ] || fail "backup too small (${SIZE} bytes < ${MIN_BYTES})"

gzip -dc "$TMP" | tail -n 2 | grep -q '^-- Dump completed' \
    || fail "dump completion marker missing (truncated dump?)"

mv "$TMP" "$FINAL" || fail "could not move backup into place"
log "OK backup saved: $FINAL (${SIZE} bytes)"

# Retention: runs only after a successful backup, so the last good backup is never lost
find "$BACKUP_DIR" -maxdepth 1 -type f -name 'appdb_*.sql.gz' -mmin +"$((RETENTION_DAYS*1440))" \
    -print -delete 2>>"$LOG" | while read -r old; do log "RETENTION removed: $old"; done

log "END"
exit 0
