# PostgreSQL 17 — Production Setup & Migration Guide
**Rocky Linux 9 | Binary Install | Standalone DB Server**
**Migration: PG 18 (Docker, Combined Server) → PG 17 (Binary, New DB Server)**

---

> **This document is written as a working guide for one operator.**
> Every step explains what is happening, why, and where to be careful, in full detail.
> Wherever a value specific to your environment is needed, a `<like-this>` placeholder is used. Replace it before you run anything.

---

## ⚠️ A Critical Note About the Migration First

Your combined server runs **PostgreSQL 18**, and the new server will have **PostgreSQL 17** installed. This is a **major version downgrade**.

PostgreSQL can be upgraded with the `pg_upgrade` tool, but it **cannot be downgraded**. So the only safe method here is:

```
pg_dump (export SQL from PG18)
       ↓
transfer to new server
       ↓
pg_restore (restore into PG17)
```

With this method:
- ✅ No data loss
- ✅ Downtime is controlled: you decide when to take the app down
- ✅ Rollback is easy: the combined server's DB is never stopped during the migration
- ⚠️ If any PG 18-specific feature or syntax is used, the restore may fail with errors. Ask the Senior DBA first

---

## The Whole Workflow (Overview)

```
Part A — New DB Server Setup
─────────────────────────────
Repository add
       ↓
PostgreSQL 17 install
       ↓
Database cluster initialize (initdb)
       ↓
postgresql.conf configure
       ↓
pg_hba.conf configure
       ↓
Service start
       ↓
postgres user password set
       ↓
Firewall port open
       ↓
pgBackRest install + configure
       ↓
New server ready ✓

Part B — Migration (Downtime Window)
──────────────────────────────────────
[Downtime starts]
Stop app containers on the combined server
       ↓
Final pg_dump on the combined server
       ↓
Transfer the dump file to the new server
       ↓
Restore on the new server
       ↓
Data verify
       ↓
Backend team updates the connection string
       ↓
Bring the application up and test
       ↓
[Downtime ends]
```

---

# Part A — PostgreSQL 17 Setup

---

## Step 1 — Add the Repository

### What is happening here?

Rocky Linux 9's default repo carries an older version of PostgreSQL. The official repository of the PostgreSQL Global Development Group (PGDG) must be added separately.

### Command

```bash
dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
```

This command installs an `.rpm` package straight from a URL; that package configures the repository for all PGDG versions.

Then disable Rocky Linux's built-in PostgreSQL module; otherwise there will be a conflict:

```bash
dnf -qy module disable postgresql
```

**Why disabling is necessary:** Rocky's AppStream has its own postgresql module. With both present, `dnf` gets confused about which to install from. To use the PGDG version, the AppStream one must be disabled.

### Verify

```bash
dnf repolist | grep pgdg
```

It shows several repos including `pgdg17`, which means it worked.

---

## Step 2 — Install PostgreSQL 17

### What gets installed

| Package | What it does |
|---------|---------|
| `postgresql17-server` | `postgres` daemon, data directory management |
| `postgresql17` | The `psql` client, `pg_dump`, `pg_restore`, all utilities |

### Command

```bash
dnf install -y postgresql17-server postgresql17
```

### Verify

```bash
psql --version
# or with the full path
/usr/pgsql-17/bin/psql --version
```

If it shows `PostgreSQL 17.x`, it worked.

---

## Step 3 — Initialize the Database Cluster (initdb)

### What is happening here?

This is a PostgreSQL-specific step; MongoDB and MySQL do not have it. Being installed does not mean PostgreSQL is ready. A "database cluster" must be created, and this process is called `initdb`.

What happens while `initdb` runs:
- The `/var/lib/pgsql/17/data/` directory is created
- System tables are created (pg_database, pg_user and so on)
- Config files are created (`postgresql.conf`, `pg_hba.conf`)
- The WAL (Write-Ahead Log) directory is created

**This is done only once, after a fresh install.**

### Command

```bash
/usr/pgsql-17/bin/postgresql-17-setup initdb
```

### The output looks like this

```
Initializing database ... OK
```

### What gets created afterwards

```
/var/lib/pgsql/17/data/
├── postgresql.conf      ← main configuration
├── pg_hba.conf          ← authentication rules
├── pg_ident.conf        ← ident mapping (usually not needed)
├── base/                ← actual database files
├── pg_wal/              ← write-ahead log files
└── log/                 ← log files (if logging_collector is on)
```

---

## Step 4 — Configure postgresql.conf

### What is happening here?

This is PostgreSQL's main config file. Everything about how the server runs is defined here: which IPs it listens on, how much memory it uses, how it writes logs, how much WAL it keeps for backups.

### Open the file

```bash
vi /var/lib/pgsql/17/data/postgresql.conf
```

### Important settings and their explanations

Find each of the settings below (they already exist in the file, commented out; remove the `#` to enable them) and set the values:

---

**Connection settings:**

```ini
listen_addresses = '*'
```

Which IPs PostgreSQL "listens" on. `'*'` means all interfaces. It is the equivalent of MongoDB's `bindIp: 0.0.0.0`.

> **In production you can be more specific:** `'127.0.0.1,<db-server-ip>'`: only localhost and the DB server's own IP. Ask your Senior DBA for their preference.

```ini
port = 5432
max_connections = 200
```

`max_connections`: the maximum number of clients that can connect at the same time. Keep it above the backend's connection pool size.

---

**Memory settings:**

```ini
shared_buffers = 256MB
effective_cache_size = 1GB
work_mem = 4MB
maintenance_work_mem = 64MB
```

> **⚠️ These values depend on the server's actual RAM.** The formulas are below:
>
> | Parameter | Rule of thumb |
> |-----------|---------------|
> | `shared_buffers` | 25% of total RAM |
> | `effective_cache_size` | 75% of total RAM |
> | `work_mem` | (RAM - shared_buffers) / max_connections |
> | `maintenance_work_mem` | 5% of RAM, max 1GB |
>
> Check the server's RAM: `free -h`
>
> Get the company standard values from the Senior DBA.

`shared_buffers`: PostgreSQL's own cache. Reading data from here avoids going to disk, so it is fast.

`effective_cache_size`: an estimate of how much OS disk cache is available. PostgreSQL does not allocate this itself; it only hints the query planner.

`work_mem`: memory for each sort/hash operation. A higher value makes queries faster, but with many connections the total memory needed grows.

---

**WAL settings, important for backups:**

```ini
wal_level = replica
archive_mode = on
archive_command = 'pgbackrest --stanza=main archive-push %p'
max_wal_senders = 3
wal_keep_size = 1GB
```

`wal_level = replica`: how much information is written into the WAL. At the `replica` level there is enough information for replication and PITR (Point-in-Time Recovery). Without it, pgBackRest will not work.

`archive_mode = on`: WAL files will be archived.

`archive_command`: this command runs each time a WAL file is complete. `%p` is replaced with the path of the WAL file. Until pgBackRest is configured this command will fail, so the service must be restarted after the pgBackRest setup (Step 8).

`max_wal_senders`: how many replication connections to allow.

`wal_keep_size`: the minimum amount of WAL to keep on disk.

---

**Logging settings:**

```ini
logging_collector = on
log_directory = 'log'
log_filename = 'postgresql-%Y-%m-%d.log'
log_rotation_age = 1d
log_rotation_size = 0
log_min_duration_statement = 1000
log_line_prefix = '%m [%p] %q%u@%d '
log_timezone = 'Asia/Dhaka'
```

`logging_collector = on`: writes logs from a background process. If it is off, logs do not go to the log file.

`log_min_duration_statement = 1000`: logs queries that take longer than 1000 ms (1 second). Useful for diagnosing slow queries.

`log_line_prefix`: what is written before each log line. `%m` = timestamp, `%p` = process ID, `%u` = username, `%d` = database name.

`log_timezone`: the timezone of the log timestamps. If your server is on UTC, use `'UTC'`. Ask the Senior DBA.

---

**Timezone:**

```ini
timezone = 'Asia/Dhaka'
```

> **⚠️ It is best to match the timezone the server is configured with.** Check the server's timezone: `timedatectl`. Ask the Senior DBA for their preference.

---

## Step 5 — Configure pg_hba.conf

### What is happening here?

`pg_hba.conf` (Host-Based Authentication) is PostgreSQL's authentication rule file. It is far more granular than MongoDB's `security: authorization: enabled`.

It defines, line by line:
- Which **type** of connection (local/network)
- To which **database**
- For which **user**
- From which **IP**
- With which **method** to authenticate

### Open the file

```bash
vi /var/lib/pgsql/17/data/pg_hba.conf
```

### Replace the whole content of the file

```conf
# TYPE    DATABASE    USER        ADDRESS                  METHOD

# Local OS: the postgres OS user can get in without a password via peer auth
# This is needed when the DBA works on the server itself
local     all         postgres                             peer

# All users from localhost, with a password
host      all         all         127.0.0.1/32             md5

# From the backend/application server
host      all         all         <backend-server-ip>/32   md5

# From the DBA's machine, via pgAdmin or psql
host      all         postgres    <dba-machine-ip>/32      md5
```

### What the authentication methods mean

| Method | What it does | When to use |
|--------|---------|-------------|
| `peer` | Allows without a password if the OS user's name matches the PG user name | Local only, for the DBA |
| `md5` | Verifies with a password hash | All remote connections |
| `scram-sha-256` | More secure than md5; recommended on PG 14+ | According to the Senior DBA's preference |

> **⚠️ To be replaced:**
> - `<backend-server-ip>`: the IP of the backend application server. Get it from the DevOps/backend team.
> - `<dba-machine-ip>`: your own machine's IP. You can get it with `curl ifconfig.me`.

### What the connection types mean

`local`: a Unix socket connection, from the same machine, inside the same OS. No network is involved.

`host`: a TCP/IP connection. It can be localhost or remote; they are told apart by the address.

---

## Step 6 — Start the Service

```bash
# Start the service
systemctl start postgresql-17

# Start automatically after a server reboot
systemctl enable postgresql-17

# Check the status
systemctl status postgresql-17
```

If you see `active (running)`, it worked.

If it fails:

```bash
# The cause will be here
journalctl -u postgresql-17 -n 50
# or
tail -50 /var/lib/pgsql/17/data/log/postgresql-$(date +%Y-%m-%d).log
```

Common causes: a wrong value in `postgresql.conf`, or an IP in `listen_addresses` that does not exist on the server.

---

## Step 7 — Set the postgres User's Password and Set Up the Application

### Set the postgres user's password

```bash
# Enter psql as the postgres OS user
sudo -u postgres psql
```

The prompt shows `postgres=#`.

```sql
-- Set the postgres superuser's password
ALTER USER postgres WITH PASSWORD '<strong_password>';

-- Exit
\q
```

> **⚠️ Put this password straight into the team password manager.**

### Create the application database and user

> **⚠️ First get the exact database name and user name from the backend team.** The pattern is given below.

```sql
sudo -u postgres psql
```

```sql
-- Create the database for the application
CREATE DATABASE <app_database_name>;

-- Create a dedicated user for the application
CREATE USER <app_user> WITH PASSWORD '<app_password>';

-- Grant the user permission on the database
GRANT ALL PRIVILEGES ON DATABASE <app_database_name> TO <app_user>;

-- On PG 15+ you must also grant schema-level permission
\c <app_database_name>
GRANT ALL ON SCHEMA public TO <app_user>;

\q
```

**Why a separate user:** if the application connects as the `postgres` superuser, it can do anything on every database, which is a security risk. `<app_user>` can work only on its own database.

---

## Step 8 — Open the Firewall Port

```bash
# Allow port 5432 from the backend server
firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="<backend-server-ip>/32" port protocol="tcp" port="5432" accept'

# For pgAdmin/psql from your DBA machine
firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="<dba-machine-ip>/32" port protocol="tcp" port="5432" accept'

# Apply
firewall-cmd --reload

# Verify
firewall-cmd --list-all
```

---

## Step 9 — Install and Configure pgBackRest

### What is happening here?

pgBackRest is a dedicated backup tool for PostgreSQL. It does two things:

**1. Continuous WAL archiving:** when PostgreSQL writes a transaction, it first writes it into a WAL (Write-Ahead Log) file. pgBackRest automatically copies these WAL files to a safe location. This makes it possible to restore the database to any specific moment (down to the minute), which is called PITR.

**2. Scheduled base backups:** takes a snapshot of the whole database. Combined with the WAL files, you can restore to any point.

### Install

```bash
dnf install -y pgbackrest
```

### Create the configuration

```bash
vi /etc/pgbackrest/pgbackrest.conf
```

```ini
[global]
# Where to keep backups
repo1-path=/var/lib/pgbackrest

# How many full backups to keep (older ones are deleted)
repo1-retention-full=2

# How many differential backups to keep
repo1-retention-diff=7

# Log settings
log-level-console=info
log-level-file=detail
log-path=/var/log/pgbackrest

# Performance
start-fast=y
delta=y

[main]
# PostgreSQL data directory
pg1-path=/var/lib/pgsql/17/data
pg1-port=5432
pg1-user=postgres
```

**`repo1-retention-full=2`**: keeps 2 full backups. When the third is taken, the oldest is deleted automatically.

**`start-fast=y`**: forces a checkpoint to start the backup, so the backup begins more quickly.

**`delta=y`**: during a restore, overwrites only what has changed; the whole directory does not have to be deleted and rewritten.

### Verify the archive_command in postgresql.conf

You set this in Step 4:

```ini
archive_command = 'pgbackrest --stanza=main archive-push %p'
```

Confirm that it is correct.

### Create and initialize the stanza

In pgBackRest, a "stanza" is the configuration block for one PostgreSQL cluster; the `[main]` section is the stanza.

```bash
# Create the stanza as the postgres user
sudo -u postgres pgbackrest --stanza=main stanza-create

# Check the archive settings of postgresql.conf
sudo -u postgres pgbackrest --stanza=main check
```

If the `check` command gives no error, WAL archiving is working properly.

> **⚠️ If the `check` command gives an error:**
> - Check that `wal_level`, `archive_mode` and `archive_command` in `postgresql.conf` are correct
> - Check that the service was restarted
> - Check the ownership of the `/var/lib/pgbackrest` directory: `ls -la /var/lib/pgbackrest`

### Take the first full backup

```bash
sudo -u postgres pgbackrest --stanza=main --type=full backup
```

How long it takes depends on the database size. If it succeeds:

```bash
sudo -u postgres pgbackrest --stanza=main info
```

It shows the details of the backup.

### Schedule it with cron

```bash
sudo -u postgres crontab -e
```

```cron
# Full backup every Sunday at 2:00 AM
0 2 * * 0 pgbackrest --stanza=main --type=full backup

# Differential backup at 2:00 AM on the other days
0 2 * * 1-6 pgbackrest --stanza=main --type=diff backup
```

**Full backup vs Differential backup:**

| Type | What it does | Size | Speed |
|------|---------|------|-------|
| Full | A copy of the whole database | Large | Slow |
| Differential | What has changed since the last full backup | Small | Fast |

WAL archiving runs continuously, so you can restore to any moment between the full/diff backups too.

---

# Part B — Migration

---

## What to Do Before Migrating

### 1. Check the data size on the source (Combined Server)

```bash
# On the combined server
docker exec <pg-container-name> psql -U postgres -c "\l+"
```

It shows the size of each database. Note the total size; it tells you how long the dump and transfer will take.

> **⚠️ To find `<pg-container-name>`:** `docker ps` shows the name of the PostgreSQL container.

### 2. Check that the new server has disk space

```bash
# On the new DB server
df -h /var/lib/pgsql
df -h /tmp
```

You need enough space in `/tmp` or another location for the dump file. Keep at least 2 times the size of the source databases as free space.

### 3. Test network connectivity

```bash
# Ping the combined server from the new DB server
ping <combined-server-ip>

# Test whether you can SSH from the combined server to the new DB server
ssh user@<new-db-server-ip> "echo 'connection ok'"
```

### 4. Tell the application team

Before starting the migration, tell the application team and stakeholders the exact downtime window.

---

## Migration — Step by Step

### Overview: what you do on which server

```
Combined Server                    New DB Server
(running)                          (ready, but empty)
    │                                    │
    │── pre-check ──────────────────────▶│
    │                                    │
[Downtime starts]                        │
    │                                    │
    │── app containers stopped           │
    │                                    │
    │── final pg_dump ──────────────────▶│ (transfer)
    │                                    │
    │   DB container keeps running       │── pg_restore
    │   (for rollback)                   │
    │                                    │── data verify
    │                                    │
    │◀── backend reconnects ────────────│
    │                                    │
[Downtime ends]                          │
```

---

### Migration Step 1: Pre-Migration Dry Run (Before Downtime)

**Do this before the actual downtime: a practice run.**

Take a test dump on the combined server without stopping the app. This dump will not be used in production, but it tells you how long the dump takes and how long the transfer takes. With that information you can estimate how long the downtime window will need to be.

```bash
# On the combined server
time docker exec <pg-container-name> pg_dumpall \
  -U postgres \
  --clean \
  --if-exists \
  > /tmp/pg_test_dump.sql

# Check the file size
ls -lh /tmp/pg_test_dump.sql

# Test the transfer speed (send to the new server, measure the time)
time scp /tmp/pg_test_dump.sql user@<new-db-server-ip>:/tmp/pg_test_dump.sql
```

The `time` command shows the total time. Knowing the total time for dump + transfer makes it easier to plan the downtime window.

**Restore the test dump on the new server to check that everything is fine:**

```bash
# On the new DB server
sudo -u postgres psql -f /tmp/pg_test_dump.sql 2>&1 | grep -i error | head -20
```

If any ERROR appears, note it and tell the Senior DBA. Any PG 18-specific syntax will be caught here, before the actual migration.

---

### Migration Step 2: Start the Downtime Window

**The time has come. Tell the application team.**

On the combined server, stop the application containers; do not stop the database container:

```bash
# On the combined server
# Stop only the frontend and backend
docker stop <frontend-container-name> <backend-container-name>

# Confirm they are stopped
docker ps
# Should show only the DB containers
```

**Why we do not stop the DB container:** from this moment no new writes arrive (the app is stopped). Not stopping the DB means rollback is always possible: if something goes wrong, just point the app back at the old DB.

---

### Migration Step 3: Take the Final Dump

With the app stopped, no new data is coming in; take the dump now. This is the authoritative final backup.

```bash
# On the combined server

# Option A: dump all databases together (recommended)
docker exec <pg-container-name> pg_dumpall \
  -U postgres \
  --clean \
  --if-exists \
  > /tmp/pg_final_$(date +%Y%m%d_%H%M%S).sql

echo "Dump completed: $(ls -lh /tmp/pg_final_*.sql)"
```

**What `pg_dumpall` does:** exports all databases, all users (roles) and all permissions into a single SQL file. Restoring this one file on the new server gives you everything.

**`--clean`:** drops existing objects first during the restore. It is not really needed on a new server, but it is good for keeping the restore idempotent.

**`--if-exists`:** when used with `--clean`, checks whether the object exists before dropping it, which avoids errors.

> **If you want to dump only specific databases** (if you want to keep a particular DB separate):
> ```bash
> docker exec <pg-container-name> pg_dump \
>   -U postgres \
>   -Fc \
>   -v \
>   -d <database_name> \
>   > /tmp/<database_name>_$(date +%Y%m%d_%H%M%S).dump
> ```
> `-Fc` = custom format (compressed, and can be restored faster with `pg_restore`)

---

### Migration Step 4: Transfer the Dump File

```bash
# From the combined server to the new DB server
scp /tmp/pg_final_*.sql user@<new-db-server-ip>:/tmp/

# Verify that the transfer succeeded
ssh user@<new-db-server-ip> "ls -lh /tmp/pg_final_*.sql"
```

The file size should be the same in both places; if it differs, the transfer is incomplete.

---

### Migration Step 5: Restore on the New Server

```bash
# On the new DB server

# Restore
sudo -u postgres psql -f /tmp/pg_final_<timestamp>.sql 2>&1 | tee /tmp/restore_log.txt

# Check for errors after the restore finishes
grep -i "^error" /tmp/restore_log.txt
```

The `tee` command shows output on screen and writes it to a file at the same time, for later review.

**Do not panic if you see some `ERROR` lines.** Some common benign errors:

| Error | Cause | Problem? |
|-------|------|----------|
| `role "postgres" already exists` | The postgres superuser already exists | ✅ Normal |
| `ERROR: database "postgres" already exists` | The default database already exists | ✅ Normal |
| `ERROR: must be owner of ...` | Permission hierarchy being restored | ⚠️ Tell the Senior DBA |
| `ERROR: syntax error` | PG18-specific syntax | ❌ Critical — Senior DBA |

---

### Migration Step 6: Verify the Data

After the restore, confirm the data arrived properly.

**On the new server:**

```bash
sudo -u postgres psql
```

```sql
-- Show all databases
\l

-- Enter each important database and look at the tables
\c <database_name>
\dt

-- Check the row counts of critical tables
SELECT COUNT(*) FROM <important_table_name>;

-- Exit
\q
```

**Run the same counts on the combined server and compare:**

```bash
docker exec <pg-container-name> psql -U postgres -d <database_name> \
  -c "SELECT COUNT(*) FROM <important_table_name>;"
```

If the counts match in both places, the migration succeeded.

> **⚠️ If the counts differ:** roll back: bring the app containers up on the combined server again and investigate.

---

### Migration Step 7: Reconnect the Application

Once the data is verified, tell the backend team; they will point the application's connection string at the new DB server.

```
Old: postgresql://postgres:<pass>@<combined-server-ip>:5432/<dbname>
New: postgresql://<app_user>:<pass>@<new-db-server-ip>:5432/<dbname>
```

Bring the application up and run a smoke test:
- Can you log in?
- Is the data visible?
- Are any DB errors appearing?

If everything is fine, **the downtime is over.**

---

### Rollback Plan

If there is a problem at any step:

```bash
# On the combined server: bring the app containers up again
docker start <frontend-container-name> <backend-container-name>
```

The combined server's DB container was never stopped, so rollback only means pointing the app back at the old connection. No data is lost.

---

## Useful Commands: Quick Reference

### Connection

```bash
# Local: as the postgres OS user (no password)
sudo -u postgres psql

# Local: with a password
psql -U postgres -h 127.0.0.1

# Remote: to a specific database
psql -h <db-server-ip> -U <user> -d <database_name>

# To connect with pgAdmin: host, port 5432, username, password
```

### Inside the psql shell

```sql
-- Show all databases  (MongoDB's show dbs)
\l

-- Switch database  (MongoDB's use dbname)
\c <database_name>

-- Show tables  (MongoDB's show collections)
\dt

-- Current database  (MongoDB's db)
SELECT current_database();

-- Current user
SELECT current_user;

-- Show all users
\du

-- Show active connections
SELECT pid, usename, application_name, client_addr, state, query
FROM pg_stat_activity
WHERE state != 'idle';

-- Kill a connection
SELECT pg_terminate_backend(<pid>);

-- Exit
\q
```

### Backup — pgBackRest

```bash
# Full backup
sudo -u postgres pgbackrest --stanza=main --type=full backup

# Differential backup
sudo -u postgres pgbackrest --stanza=main --type=diff backup

# List backups
sudo -u postgres pgbackrest --stanza=main info

# Verify that everything is fine
sudo -u postgres pgbackrest --stanza=main check
```

### User and Permission Management

```sql
-- Change a password
ALTER USER <username> WITH PASSWORD '<new_password>';

-- Create a user
CREATE USER <username> WITH PASSWORD '<password>';

-- Create a database
CREATE DATABASE <dbname> OWNER <username>;

-- Grant permission
GRANT ALL PRIVILEGES ON DATABASE <dbname> TO <username>;
GRANT ALL ON SCHEMA public TO <username>;

-- Delete a user
DROP USER <username>;

-- Delete a database (with caution)
DROP DATABASE <dbname>;
```

### Viewing Logs

```bash
# Live log
tail -f /var/lib/pgsql/17/data/log/postgresql-$(date +%Y-%m-%d).log

# Slow queries
grep "duration:" /var/lib/pgsql/17/data/log/postgresql-$(date +%Y-%m-%d).log | sort -t= -k2 -rn | head -20

# Errors
grep "^.*ERROR" /var/lib/pgsql/17/data/log/postgresql-$(date +%Y-%m-%d).log

# pgBackRest log
tail -f /var/log/pgbackrest/main-backup.log
```

### Service Management

```bash
systemctl start postgresql-17
systemctl stop postgresql-17
systemctl restart postgresql-17
systemctl reload postgresql-17   # reload config, without a service restart
systemctl status postgresql-17
```

---

## Key File Locations

| What | Where |
|----|--------|
| Main config | `/var/lib/pgsql/17/data/postgresql.conf` |
| Auth config | `/var/lib/pgsql/17/data/pg_hba.conf` |
| Data directory | `/var/lib/pgsql/17/data/` |
| Log directory | `/var/lib/pgsql/17/data/log/` |
| WAL directory | `/var/lib/pgsql/17/data/pg_wal/` |
| pgBackRest config | `/etc/pgbackrest/pgbackrest.conf` |
| pgBackRest backup | `/var/lib/pgbackrest/` |
| pgBackRest log | `/var/log/pgbackrest/` |
| Binary location | `/usr/pgsql-17/bin/` |

---

## Uninstall (when needed)

> **⚠️ Running this permanently deletes all data.**

```bash
systemctl stop postgresql-17
systemctl disable postgresql-17
dnf remove -y postgresql17-server postgresql17
rm -rf /var/lib/pgsql/17/data
rm -rf /var/log/postgresql
```

---

## Things You Need to Know in Advance

- [ ] **The DB server's own IP**: get it with `ip addr show`
- [ ] **The backend server's IP**: get it from the DevOps/backend team
- [ ] **Your DBA machine's IP**: `curl ifconfig.me`
- [ ] **The name of the PG container on the combined server**: `docker ps`
- [ ] **Which databases need to be migrated**: the backend team will confirm
- [ ] **The application user's name and password**: get them from the backend team or create new ones
- [ ] **The server's RAM**: check with `free -h`, for the memory config
- [ ] **Timezone**: check with `timedatectl`
- [ ] **Memory config values**: get the company standard from the Senior DBA
- [ ] **Authentication method (md5 vs scram-sha-256)** — Senior DBA preference
- [ ] **Downtime window**: agree it with the application team
- [ ] **Rollback decision maker**: decide in advance who will decide on rollback if there is a problem in the migration

---

*End of document | PostgreSQL 17 | Rocky Linux 9 | Migration from PG 18*
