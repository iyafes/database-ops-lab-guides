#!/bin/sh
# Start cron (busybox crond), then the nested Docker daemon (unix socket only).
set -eu
crond -b -l 8 -L /var/log/crond.log
exec dockerd-entrypoint.sh dockerd --host=unix:///var/run/docker.sock
