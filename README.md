# Database Ops Lab Guides

Step-by-step setup and operations guides for PostgreSQL, MySQL, MariaDB, MongoDB, Redis, Cassandra and ScyllaDB, written while building and practising these setups in a virtual-machine lab (Rocky Linux 9 and Ubuntu 24.04 LTS).

> **Lab material, not production runbooks.** All IP addresses, hostnames, usernames and passwords in these guides are examples or `<PLACEHOLDERS>`. Replace them with your own values, and test every procedure in a non-production environment first.

## Featured

**[MariaDB in Docker: automated remote backup over SSH](mariadb/mariadb-remote-backup-over-ssh.md)** — a complete workbook with a runnable two-host lab ([`mariadb/remote-backup-lab/`](mariadb/remote-backup-lab/)).

- **Design:** pull model over SSH, no published database port, a dedicated read-only DB user, a root-owned wrapper with a one-command `sudoers` rule, and the credential passed over stdin so it never touches a command line, `cron` or a log.
- **Reliability:** `flock` against overlapping runs, exit code of every pipeline stage (`PIPESTATUS`), atomic `.part` → `mv`, four verification layers, retention that only runs after a successful backup.
- **Proof, from a lab run on 2026-11-19:** restore into a disposable container with `CHECKSUM TABLE` identical on all 5 tables; a dump taken under concurrent writes restored consistently (11,482 = 11,482 rows); 3 real `cron` runs; 6 deliberate failure drills; an independent freshness check that catches zero-byte and truncated backups; an SSH forced-command hardening step; a tested restore after damage.

## Skills map: CV topics and the lab guides that reproduce them

The skills on my CV, practised independently in a lab with generated test data. These guides show how I work through each topic; they are not descriptions of any employer's systems.

| Topic | Lab guides |
|---|---|
| Backup, WAL archiving and PITR (pgBackRest, Barman) | [pgBackRest remote repository](postgresql/backup-and-recovery/pgbackrest-remote-repo-and-mongodb-backup.md) · [Barman](postgresql/backup-and-recovery/barman-backup.md) · [WAL archiving and PITR](postgresql/backup-and-recovery/wal-archiving-and-pitr.md) |
| Backup automation, verification and restore testing | [MariaDB remote backup over SSH](mariadb/mariadb-remote-backup-over-ssh.md) · [pg_dump and pg_restore](postgresql/backup-and-recovery/pg-dump-and-restore.md) · [MariaDB in Docker: remote backup over SSH](mariadb/mariadb-remote-backup-over-ssh.md) |
| MongoDB backups and replica sets | [pgBackRest + MongoDB backup](postgresql/backup-and-recovery/pgbackrest-remote-repo-and-mongodb-backup.md) · [MongoDB replica set](mongodb/mongodb-replica-set.md) |
| High availability (Patroni, etcd, HAProxy) | [Patroni + etcd + HAProxy + pgBackRest cluster](postgresql/replication-and-ha/patroni-etcd-haproxy-pgbackrest-cluster.md) |
| Security hardening and auditing | [pgAudit](postgresql/security-and-monitoring/pgaudit.md) · [User and role administration](postgresql/security-and-monitoring/user-and-role-administration.md) · [MariaDB forced-command SSH key](mariadb/mariadb-remote-backup-over-ssh.md#72-bind-the-ssh-key-to-one-command-forced-command--tested) |
| Replication and distributed databases | [MySQL replication](mysql/mysql-setup-and-source-replica-replication.md) · [Redis Cluster](redis/redis-cluster-3-vm-6-node.md) · [Cassandra](cassandra-scylladb/cassandra-3-node-cluster.md) · [ScyllaDB](cassandra-scylladb/scylladb-3-node-cluster.md) |
| Linux and operations | [Linux command reference](linux-and-ops/linux-command-reference.md) · [Storage and partitioning](linux-and-ops/storage-partitioning-apache-nginx.md) |

## Contents

### PostgreSQL

| Topic | Guide |
|---|---|
| Installation | [PostgreSQL install SOP (Rocky Linux)](postgresql/installation/pg-install-sop-rocky.md) · [(Ubuntu)](postgresql/installation/pg-install-sop-ubuntu.md) · [PostgreSQL 17 on Rocky with separate data/log disks](postgresql/installation/pg17-rocky-custom-disks-install.md) · [PostgreSQL 17 setup and migration](postgresql/installation/pg17-production-setup-and-migration.md) |
| Replication and HA | [Streaming replication](postgresql/replication-and-ha/pg-streaming-replication.md) · [Patroni + etcd + HAProxy + pgBackRest cluster](postgresql/replication-and-ha/patroni-etcd-haproxy-pgbackrest-cluster.md) · [Patroni cluster best practices](postgresql/replication-and-ha/patroni-cluster-best-practices.md) · [Adding a reporting node to an HA cluster](postgresql/replication-and-ha/add-reporting-node-to-ha-cluster.md) · [Pgpool-II with streaming replication](postgresql/replication-and-ha/pgpool-ii-with-streaming-replication.md) ([extended](postgresql/replication-and-ha/pgpool-ii-with-streaming-replication-extended.md)) |
| Backup and recovery | [pgBackRest remote repository + MongoDB backup](postgresql/backup-and-recovery/pgbackrest-remote-repo-and-mongodb-backup.md) · [Barman](postgresql/backup-and-recovery/barman-backup.md) · [WAL archiving and PITR](postgresql/backup-and-recovery/wal-archiving-and-pitr.md) · [pg_basebackup](postgresql/backup-and-recovery/pg-basebackup.md) · [pg_dump and pg_restore](postgresql/backup-and-recovery/pg-dump-and-restore.md) |
| Security and monitoring | [pgAudit](postgresql/security-and-monitoring/pgaudit.md) · [pgBadger](postgresql/security-and-monitoring/pgbadger.md) · [User and role administration](postgresql/security-and-monitoring/user-and-role-administration.md) |

### Other databases

| Database | Guide |
|---|---|
| MySQL 8.4 | [Setup and source–replica replication](mysql/mysql-setup-and-source-replica-replication.md) |
| MariaDB 11.8 | [Remote backup over SSH: Docker, pull model, verified restore, failure drills](mariadb/mariadb-remote-backup-over-ssh.md) · [two-host lab and scripts](mariadb/remote-backup-lab/) |
| MongoDB 8.0 | [Server setup](mongodb/mongodb8-server-setup.md) · [Production setup](mongodb/mongodb8-production-setup.md) · [3-node replica set](mongodb/mongodb-replica-set.md) |
| Redis | [Redis Cluster: 3 VMs, 6 nodes](redis/redis-cluster-3-vm-6-node.md) |
| Cassandra / ScyllaDB | [Cassandra 3-node cluster](cassandra-scylladb/cassandra-3-node-cluster.md) · [ScyllaDB 3-node cluster](cassandra-scylladb/scylladb-3-node-cluster.md) |

### Cloud, Linux and overview

| Topic | Guide |
|---|---|
| AWS | [S3 ↔ RDS (PostgreSQL) data pipeline](aws/s3-rds-postgresql-data-pipeline.md) |
| Linux | [Command reference](linux-and-ops/linux-command-reference.md) · [User and group management](linux-and-ops/user-and-group-management.md) · [Storage, partitioning, Apache and Nginx](linux-and-ops/storage-partitioning-apache-nginx.md) |
| Overview | [Cluster architectures compared](overview/db-clusters-overview.md) |

## Notes

- **Lab environment:** guides were written against VMs, not cloud-native or Kubernetes deployments.
- **Runnable lab:** `mariadb/remote-backup-lab/` contains scripts and a Docker-based two-host lab. Its containers are privileged; use a disposable machine only.
- **Placeholders:** values such as `<ADMIN_PASSWORD>` must be replaced before use.
- **Reference-only section:** the MySQL InnoDB Cluster section in the overview is an architecture reference. The hands-on MySQL guide here covers source–replica replication.
- **Language:** all guides are in English.

## Author

Abdullah Al Masud · [LinkedIn](https://linkedin.com/in/almasud-abdullah)
