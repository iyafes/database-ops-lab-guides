# Remote-backup lab: two hosts on one machine

Companion to [`../mariadb-remote-backup-over-ssh.md`](../mariadb-remote-backup-over-ssh.md). It reproduces the guide's topology with two containers that each run their own Docker daemon (Docker-in-Docker):

| Host | Container | IP | Role |
|---|---|---|---|
| `source-db` | `lab-source-db` | `192.168.50.10` | `sshd`, `sudo`, Docker; runs the `appdb-db` MariaDB container |
| `backup-host` | `lab-backup-host` | `192.168.50.20` | SSH client, `crond`, `flock`, Docker (restore tests) |

> **Lab only.** Both containers are `privileged: true`. Use a disposable machine, never a shared or production Docker host. The database holds generated test data; the only credentials are throw-away values you create during the lab.

## Use

```bash
docker compose up -d --build

docker pull mariadb:11.8
docker save mariadb:11.8 | docker exec -i lab-source-db docker load
docker save mariadb:11.8 | docker exec -i lab-backup-host docker load

# then follow Part 5 of the guide, starting at Phase 0
docker exec -it lab-source-db bash                 # [SOURCE]
docker exec -it -u backupadm lab-backup-host bash  # [BACKUP]

docker compose down -v                             # remove everything when done
```

## Files

| Path | What it is |
|---|---|
| `compose.yaml` | The two hosts on a `192.168.50.0/24` network |
| `source/`, `backup/` | Image definitions (Alpine-based `docker:dind` plus the tools the guide needs) |
| `scripts/appdb-mariadb-dump.sh` | Source-side wrapper (install as `/usr/local/sbin/appdb-mariadb-dump.sh`, root, `750`) |
| `scripts/appdb-mariadb-backup.sh` | Backup-side pull script (install as `/usr/local/bin/appdb-mariadb-backup.sh`) |
| `scripts/appdb-backup-check.sh` | Independent freshness and health check |
| `scripts/seed-appdb.sql` | Generated test data (5 tables, one Unicode row) |

## Differences from real VMs

The hosts are Alpine containers, so there is no systemd (`systemctl`, `journalctl`) and no `apt`; BusyBox `crond` is started directly. The guide lists every difference in [Part 4.3](../mariadb-remote-backup-over-ssh.md#43-how-the-lab-differs-from-two-ubuntudebian-vms).
