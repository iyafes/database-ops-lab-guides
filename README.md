# Database Ops Lab Guides

Step-by-step setup and operations guides for PostgreSQL, MySQL, MongoDB, Redis, Cassandra and ScyllaDB, written while building and practising these setups in a virtual-machine lab (Rocky Linux 9 and Ubuntu 24.04 LTS).

> **Lab material, not production runbooks.** All IP addresses, hostnames, usernames and passwords in these guides are examples or `<PLACEHOLDERS>`. Replace them with your own values, and test every procedure in a non-production environment first.

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
- **Placeholders:** values such as `<ADMIN_PASSWORD>` must be replaced before use.
- **Reference-only section:** the MySQL InnoDB Cluster section in the overview is an architecture reference. The hands-on MySQL guide here covers source–replica replication.
- **Language:** a few guides contain Bengali explanations alongside the commands (the MongoDB production setup, the PostgreSQL 17 setup and migration guide, and part of the Patroni guide).

## Author

Abdullah Al Masud · [LinkedIn](https://linkedin.com/in/almasud-abdullah)
