#!/bin/bash
# SOURCE host. Installed as /usr/local/sbin/appdb-mariadb-dump.sh (root:root, 750).
# Streams a consistent logical dump of database "appdb" to stdout. Takes no arguments.
# The DB credential never leaves this host: it travels over stdin into the container,
# lands in a short-lived 600 temp file, and is removed on exit.
set -euo pipefail

CNF="/etc/appdb-backup/backup.cnf"
CONTAINER="appdb-db"

if [ ! -r "$CNF" ]; then
    echo "ERROR: credential file $CNF not readable" >&2
    exit 1
fi

exec /usr/bin/docker exec -i "$CONTAINER" sh -c '
umask 077
f=$(mktemp) || exit 1
trap "rm -f $f" EXIT
cat > "$f"
mariadb-dump --defaults-extra-file="$f" \
  --single-transaction --quick --events --triggers \
  --hex-blob --default-character-set=utf8mb4 appdb
' < "$CNF"
