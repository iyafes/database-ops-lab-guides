#!/bin/sh
# Start sshd, then the nested Docker daemon (unix socket only, no TCP listener).
set -eu
ssh-keygen -A >/dev/null
/usr/sbin/sshd
exec dockerd-entrypoint.sh dockerd --host=unix:///var/run/docker.sock
