#!/bin/bash
# BACKUP host. Installed as /usr/local/bin/appdb-backup-check.sh. Run from cron, separately from the backup job.
# Answers one question: "is there a recent, healthy backup?" A backup job that fails silently is the real risk,
# so this check looks at the files on disk instead of trusting the backup script's own log.
# Exit codes: 0 = OK, 2 = CRITICAL (message on stdout, one line per problem).
set -uo pipefail

BACKUP_DIR="${BACKUP_DIR:-/backup/mariadb}"
MAX_AGE_MIN="${MAX_AGE_MIN:-960}"     # 16 h: covers a 12 h schedule plus slack
MIN_BYTES="${MIN_BYTES:-10240}"

problems=()

# 1. Any zero-byte backup file is a failed run that looked like a success
while IFS= read -r f; do
    problems+=("zero-byte backup file: $f")
done < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name 'appdb_*.sql.gz' -size 0)

# 2. Newest backup must exist, be fresh, big enough and pass gzip -t
newest="$(find "$BACKUP_DIR" -maxdepth 1 -type f -name 'appdb_*.sql.gz' -size +0 -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n 1 | cut -d' ' -f2-)"
if [ -z "$newest" ]; then
    problems+=("no backup file found in $BACKUP_DIR")
else
    age_min=$(( ( $(date +%s) - $(stat -c %Y "$newest") ) / 60 ))
    size=$(stat -c %s "$newest")
    [ "$age_min" -le "$MAX_AGE_MIN" ] || problems+=("newest backup is ${age_min} min old (limit ${MAX_AGE_MIN}): $newest")
    [ "$size" -ge "$MIN_BYTES" ]      || problems+=("newest backup too small (${size} bytes): $newest")
    gzip -t "$newest" 2>/dev/null     || problems+=("newest backup fails gzip -t: $newest")
fi

# 3. The most recent result line in the log (OK or FAILED) must be OK.
#    Older failures that were followed by a good run are history, not a current problem.
if [ -f "$BACKUP_DIR/backup.log" ]; then
    last_result="$(grep -E '\] (OK|FAILED)' "$BACKUP_DIR/backup.log" | tail -n 1)"
    case "$last_result" in
        *FAILED*) problems+=("last backup run failed: ${last_result#* }") ;;
    esac
fi

if [ "${#problems[@]}" -eq 0 ]; then
    echo "OK newest=$newest age=${age_min}min size=${size}B"
    exit 0
fi
printf 'CRITICAL %s\n' "${problems[@]}"
exit 2
