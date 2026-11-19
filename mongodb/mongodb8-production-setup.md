# MongoDB 8.0 — Production Setup Guide
**Rocky Linux 9 | Binary Install | Standalone Server**

---

> **This document is written as a working guide for one operator.**
> Every step explains what is happening, why, and where to be careful, in full detail.
> Wherever a value specific to your environment is needed (IP, password, database name), a `<like-this>` placeholder is used. Replace it before you run anything.

---

## The Whole Workflow (Overview)

```
Repository add
     ↓
MongoDB install
     ↓
mongod.conf configure
     ↓
Service start
     ↓
Create admin user  ←── via the localhost exception
     ↓
Verify authorization (restart)
     ↓
Replica set initiate
     ↓
Firewall port open
     ↓
Create app database + user
     ↓
Backup setup
```

---

## Step 1 — Add the Repository

### What is happening here?

Rocky Linux 9's default package list does not contain MongoDB, or only a much older version. So MongoDB's own official repository has to be added separately, so that `dnf install` knows where to fetch MongoDB 8.0 from.

The repository file goes in `/etc/yum.repos.d/`; `dnf` reads everything in this folder automatically.

### Command

```bash
cat > /etc/yum.repos.d/mongodb-org-8.0.repo << 'EOF'
[mongodb-org-8.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/9/mongodb-org/8.0/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-8.0.asc
EOF
```

### What each line means

| Line | Meaning |
|------|------|
| `[mongodb-org-8.0]` | The repository's internal ID; any unique name works |
| `name=MongoDB Repository` | A human-readable label only |
| `baseurl=...` | Where packages are downloaded from; `/9/` means Rocky Linux 9 (EL9) |
| `gpgcheck=1` | Verifies that the downloaded package really comes from MongoDB and was not tampered with |
| `gpgkey=...` | MongoDB's official public key used for that verification |

### Verify

```bash
cat /etc/yum.repos.d/mongodb-org-8.0.repo
```

It shows the file's content; if it looks right, move on to the next step.

---

## Step 2 — Install MongoDB

### What is happening here?

Installing `mongodb-org` brings in several components at once:

| Component | What it does |
|-----------|---------|
| `mongod` | MongoDB's main server daemon; runs in the background and handles all data |
| `mongosh` | Interactive shell; type commands here to manage the database |
| `mongodump` | Backup tool |
| `mongorestore` | Restore tool |
| `mongostat` | Tool for live statistics |

### Command

```bash
dnf install -y mongodb-org
```

The `-y` flag means "answer yes to every confirmation automatically", so you do not have to press Enter manually.

### Verify the installation

```bash
mongod --version
mongosh --version
```

If both show a version number, the installation succeeded.

---

## Step 3 — Configure mongod.conf

### What is happening here?

`/etc/mongod.conf` is MongoDB's main configuration file. When the server starts, it reads this file to learn:
- Where to keep data
- Where to write logs
- Which IPs to accept connections from
- Whether a password is required
- What the replica set is called

**This must be configured before the service is started.**

### Open the file

```bash
vi /etc/mongod.conf
```

> **Basics of working in the vi editor:**
> - Press `i` for insert mode; you can type only in this mode
> - Press `Esc` to leave insert mode
> - Type `:wq` and press Enter to save and exit
> - Type `:q!` and press Enter to exit without saving

### The complete config (replace the file content with this)

```yaml
# ─── Storage ───────────────────────────────────────────────────
storage:
  dbPath: /var/lib/mongo

# ─── System Log ────────────────────────────────────────────────
systemLog:
  destination: file
  logAppend: true
  path: /var/log/mongodb/mongod.log

# ─── Network ───────────────────────────────────────────────────
net:
  port: 27017
  bindIp: 127.0.0.1,<db-server-own-ip>

# ─── Security ──────────────────────────────────────────────────
security:
  authorization: enabled

# ─── Operation Profiling ───────────────────────────────────────
operationProfiling:
  slowOpThresholdMs: 100

# ─── Replication ───────────────────────────────────────────────
replication:
  replSetName: "rs0"
```

### Detailed explanation of each section

---

**`storage` section**

```yaml
storage:
  dbPath: /var/lib/mongo
```

`dbPath`: MongoDB's actual data files (BSON format) live here. Make sure this folder has enough space.

Journaling: every write operation is first written to a "log" (the journal) and only then to the actual data file, so after a sudden crash data can be recovered from the journal. On MongoDB 8.0 the journal is always on; the old `storage.journal.enabled` option was removed in 6.1, and putting it in `mongod.conf` can stop mongod from starting.

---

**`systemLog` section**

```yaml
systemLog:
  destination: file
  logAppend: true
  path: /var/log/mongodb/mongod.log
```

`destination: file`: where the log goes. `file` means it is written to a file.

`logAppend: true`: when the server restarts, new log lines are appended to the existing log instead of starting a fresh file. If this is not `true`, all logs from before the restart are lost.

`path`: the location of the log file.

---

**`net` section**

```yaml
net:
  port: 27017
  bindIp: 127.0.0.1,<db-server-own-ip>
```

`port: 27017`: MongoDB's default port. It is not usually changed.

`bindIp`: the IP addresses MongoDB "listens" on.
- `127.0.0.1`: localhost, so connections from the same server work
- `<db-server-own-ip>`: the DB server's own IP; with this, other servers (the backend server) can connect

> **⚠️ Replace `<db-server-own-ip>`.** To find the DB server's actual IP:
> ```bash
> ip addr show
> # or
> hostname -I
> ```
> Use the IP it shows.

> **Why you should not use `0.0.0.0`:** `0.0.0.0` accepts connections from every IP, including the internet. In production, give specific IPs.

---

**`security` section**

```yaml
security:
  authorization: enabled
```

This is MongoDB's most important security setting. By default, MongoDB lets anyone connect **without any password**. With `authorization: enabled`, nobody can get in without a valid username and password.

> **Note on order:** with `authorization: enabled` and no users yet, MongoDB's localhost exception lets you create the first (admin) user from a shell on the server itself. Until that user exists, remote clients can do nothing useful.
>
> This guide creates the admin user right after the first start, then verifies that authentication is required.

---

**`operationProfiling` section**

```yaml
operationProfiling:
  slowOpThresholdMs: 100
```

Queries that take more than 100 ms are marked as "slow operation" in the log. This helps diagnose performance problems.

---

**`replication` section**

```yaml
replication:
  replSetName: "rs0"
```

Why this is needed even on a single server:
- **The oplog is enabled.** The oplog is an ordered log of all write operations. It is what makes `mongodump --oplog` (a consistent point-in-time dump) possible.
- **Later**, if you add another server to build a real replica set, you can do it without migrating the data.

The name `"rs0"` is a convention. You can change it, but the same name must match when you initiate later.

---

## Step 4 — Start the Service

### What is happening here?

`systemctl` is Linux's service manager. It starts, stops and restarts services, and sets whether a service starts automatically at boot.

### Commands

```bash
# Start the service
systemctl start mongod

# Start automatically after a server reboot; without this you must start it manually after a restart
systemctl enable mongod

# Check the status
systemctl status mongod
```

### What the status output should show

```
● mongod.service - MongoDB Database Server
   Active: active (running) since ...
```

If you see `active (running)`, everything is fine.

### If it shows `failed`

```bash
# Check the log; the cause will be there
tail -50 /var/log/mongodb/mongod.log
```

Common causes: wrong yaml formatting in `mongod.conf`, or a wrong IP in `bindIp`.

---

## Step 5 — Create the Admin User

### What is happening here?

The service was started in Step 4 with `authorization: enabled` already in the config, but no user exists yet. In this state the localhost exception applies: from a shell on the server itself you may create the first user (in the `admin` database), and nothing else is allowed. Use this to create the admin user.

Once the admin user exists, the exception no longer applies and every connection must authenticate.

### Enter the shell

```bash
mongosh
```

The prompt changes to `test>`, which means you are in the shell.

### Create the admin user

```javascript
use admin

db.createUser({
  user: "admin",
  pwd: "<admin_er_jonno_strong_password>",
  roles: [{ role: "root", db: "admin" }]
})
```

**What each part means:**

`use admin`: switch to the `admin` database. This is MongoDB's special system database; all administrative users live here.

`user: "admin"`: the username. Any name works.

`pwd: "..."`: the password. In production use a strong password: uppercase, lowercase, numbers and special characters.

`roles: [{ role: "root", db: "admin" }]`: the `root` role means permission to do everything on every database. It is only for the DBA; an application user is never given `root`.

### On success it shows

```
{ ok: 1 }
```

### Leave the shell

```javascript
exit
```

---

## Step 6 — Restart to Activate Authorization

Authorization has been active since Step 4. Restarting here is not strictly required, but it confirms the setting survives a restart.

```bash
systemctl restart mongod
```

### Verify that authorization works

Try connecting without a password; it should be rejected:

```bash
mongosh --eval "db.adminCommand({ listDatabases: 1 })"
```

It should now give an `Unauthorized` error. That is what we want: authorization is working correctly.

Now verify with the admin password that the admin user can get in:

```bash
mongosh -u admin -p <password> --authenticationDatabase admin --eval "db.adminCommand({ listDatabases: 1 })"
```

If it shows the database list, everything is fine.

---

## Step 7 — Initiate the Replica Set

### What is happening here?

We set `replSetName: "rs0"` in `mongod.conf`. That says "I want to be part of a replica set named rs0". But setting it in the config is not enough; it must be explicitly initiated once.

Running `rs.initiate()`:
- Makes this node PRIMARY
- Enables the oplog
- Officially creates the replica set

### Log in as admin

```bash
mongosh -u admin -p <password> --authenticationDatabase admin
```

### Initiate

```javascript
rs.initiate()
```

### The output looks like this

```json
{
  ok: 1,
  operationTime: ...,
  ...
}
```

The prompt changes to `rs0 [direct: primary]>`. That confirms the replica set is running and this node is PRIMARY.

### Verify the status

```javascript
rs.status()
```

If the output shows `"stateStr": "PRIMARY"`, it succeeded.

### Leave the shell

```javascript
exit
```

---

## Step 8 — Open the Firewall Port

### What is happening here?

On Rocky Linux 9, `firewalld` is enabled by default and blocks all incoming connections. Unless MongoDB's port 27017 is explicitly opened, the backend server cannot connect.

But opening it to everyone is not safe; open it only for the specific IP (the backend server).

### Command

```bash
# Allow connections on port 27017 only from the backend server's IP
firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="<backend-server-ip>/32" port protocol="tcp" port="27017" accept'

# Apply the rule
firewall-cmd --reload
```

> **⚠️ Replace `<backend-server-ip>`.** It is the IP of the server from which the backend application will connect to MongoDB. Confirm it with the backend team or the DevOps team.

> **What `/32` means:** a single IP address; only connections from that one IP are allowed. For a range, use something like `/24`.

### Verify

```bash
firewall-cmd --list-all
```

The `rich rules` section of the output should show your rule.

### If you need access from your own machine

As the DBA, if you want to connect from your local machine with some tool:

```bash
firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="<tomar-machine-ip>/32" port protocol="tcp" port="27017" accept'
firewall-cmd --reload
```

---

## Step 9 — Create the Application Database and User

### What is happening here?

The application should not connect with the admin user; that is a security risk. Create a separate user for each application or service, with permission only on its own database.

### Log in

```bash
mongosh -u admin -p <password> --authenticationDatabase admin
```

### Create the database and user

> **⚠️ First confirm with the backend team which databases your application needs.** An example pattern is given below.

```javascript
// Switch to the database you are creating the user in
use <database_name>

// Create the user, with readWrite permission on this database only
db.createUser({
  user: "<app_user_name>",
  pwd:  "<app_user_password>",
  roles: [{ role: "readWrite", db: "<database_name>" }]
})
```

**What the `readWrite` role means:**
- Can read data (equivalent to SELECT)
- Can write data (equivalent to INSERT/UPDATE/DELETE)
- Cannot drop the database
- Cannot create other users
- Cannot see other databases

### Create a collection (optional)

In MongoDB, a collection is created automatically on the first insert. But you can create it explicitly to confirm:

```javascript
use <database_name>
db.createCollection("<collection_name>")
```

A collection is the equivalent of a table in a relational database, but without a fixed schema.

### Verify the app user's connection

In a new terminal, or after exiting:

```bash
mongosh -u <app_user_name> -p <app_user_password> --authenticationDatabase <database_name>
```

If it connects, it worked. Trying to enter another database with this user should give `Unauthorized`, which is expected.

---

## Step 10 — Set Up Backups

### What is happening here?

`mongodump` is MongoDB's official backup tool. It exports all data in BSON format, which can later be restored into a MongoDB server with `mongorestore` (restoring into an older major version is not guaranteed to work).

### Manual backup (can be run at any time)

```bash
mongodump \
  --authenticationDatabase admin \
  -u admin \
  -p <password> \
  --out /var/backups/mongodb/$(date +%Y%m%d_%H%M%S) \
  --gzip
```

`--gzip`: compresses the output. The size drops a lot.

`$(date +%Y%m%d_%H%M%S)`: puts a timestamp in the folder name, for example `20250405_143022`.

### Create the automated daily backup script

```bash
cat > /usr/local/bin/mongo_backup.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/var/backups/mongodb"
DATE=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS=7

mkdir -p "$BACKUP_DIR"

mongodump \
  --authenticationDatabase admin \
  -u admin \
  -p "<password>" \
  --out "$BACKUP_DIR/backup_$DATE" \
  --gzip

# Delete old backups (older than 7 days)
find "$BACKUP_DIR" -maxdepth 1 -type d -mtime +$RETENTION_DAYS -exec rm -rf {} \;

echo "$(date): Backup completed — $BACKUP_DIR/backup_$DATE" >> /var/log/mongo_backup.log
EOF
```

> **⚠️ Replace `<password>` in the script.** Put the admin's actual password. Note that a password given with `-p` is visible in the process list while `mongodump` runs; a `--config` file with mode 600 avoids that.

Make the script executable:

```bash
chmod 700 /usr/local/bin/mongo_backup.sh
```

`chmod 700`: only the owner (root) can read, write and execute. Nobody else can see the file's content, which matters because it contains a password.

### Schedule it with cron

```bash
crontab -e
```

Add this line:

```cron
0 3 * * * /usr/local/bin/mongo_backup.sh
```

**Cron syntax:** `minute hour day month day_of_week`

`0 3 * * *` = every day at 3:00 AM. `*` means "every".

### Test the backup manually

```bash
/usr/local/bin/mongo_backup.sh

# Check the log
cat /var/log/mongo_backup.log

# Check the backup folder
ls -lh /var/backups/mongodb/
```

### Restore procedure (when needed)

```bash
mongorestore \
  --authenticationDatabase admin \
  -u admin \
  -p <password> \
  --drop \
  --gzip \
  /var/backups/mongodb/<backup_folder_name>
```

`--drop`: drops the existing collection before restoring, which avoids duplicate documents. If you want to keep existing data and merge, leave out `--drop`.

---

## Useful Commands: Quick Reference

### Connection

```bash
# Log in as admin
mongosh -u admin -p <password> --authenticationDatabase admin

# Log in as the app user
mongosh -u <user> -p <password> --authenticationDatabase <database_name>

# Connect from a remote server
mongosh --host <db-server-ip> --port 27017 -u admin -p <password> --authenticationDatabase admin
```

### Inside the shell

```javascript
// Show all databases
show dbs

// Switch database
use <database_name>

// Show the current database
db

// Show collections
show collections

// Replica set status
rs.status()

// Server statistics
db.serverStatus()

// Show active operations
db.currentOp({ "active": true })

// Leave the shell
exit
```

### User Management

```javascript
// Show all users (from the admin database)
use admin
db.system.users.find().pretty()

// Change a password
db.changeUserPassword("<username>", "<new_password>")

// Give a user an extra role
db.grantRolesToUser("<username>", [{ role: "readWrite", db: "<another_db>" }])

// Delete a user
use <database_where_user_was_created>
db.dropUser("<username>")
```

### Viewing logs

```bash
# Live log
tail -f /var/log/mongodb/mongod.log

# Only the slow operations
tail -f /var/log/mongodb/mongod.log | grep -i "slow"

# Errors
grep -i "error\|failed" /var/log/mongodb/mongod.log

# Backup log
tail -f /var/log/mongo_backup.log
```

### Service Management

```bash
systemctl start mongod
systemctl stop mongod
systemctl restart mongod
systemctl status mongod
```

---

## MongoDB Roles: Which One to Give to Whom

| Role | What it can do | Give it to |
|------|---------|-----------|
| `root` | Everything on all databases | Only the DBA admin user |
| `readWrite` | Read + write on a specific database | The application user |
| `read` | Read only on a specific database | Reporting or read-only tools |
| `dbAdmin` | Index creation, schema management; no data access | A developer who manages the schema |
| `userAdmin` | Create/manage users on a specific database | A secondary admin |

---

## Key File Locations

| What | Where |
|----|--------|
| Configuration file | `/etc/mongod.conf` |
| Data directory | `/var/lib/mongo` |
| Log file | `/var/log/mongodb/mongod.log` |
| Repository file | `/etc/yum.repos.d/mongodb-org-8.0.repo` |
| Backup script | `/usr/local/bin/mongo_backup.sh` |
| Backup output | `/var/backups/mongodb/` |
| Backup log | `/var/log/mongo_backup.log` |

---

## Complete Uninstall (when needed)

> **⚠️ Running this permanently deletes all data. Take a verified backup first.**

```bash
systemctl stop mongod
systemctl disable mongod
dnf erase -y $(rpm -qa | grep mongodb-org)
rm -rf /var/lib/mongo
rm -rf /var/log/mongodb
rm -f /etc/mongod.conf
```

---

## Things You Need to Know in Advance

These cannot be provided in this guide; they depend on your specific environment:

- [ ] **The DB server's own IP**: get it with `ip addr show`; it goes into `bindIp`
- [ ] **The backend server's IP**: get it from the DevOps or backend team; needed for the firewall rule
- [ ] **Which databases are needed**: get the exact database names from the backend team
- [ ] **Which application users are needed**: ask the backend team for the users and which database each needs access to
- [ ] **What the admin password will be**: choose a strong password and store it in the team password manager
- [ ] **How long to keep backups**: adjust `RETENTION_DAYS` in the script (default is 7 days)
- [ ] **When backups run**: change the cron schedule if 3 AM is not suitable

---

*End of document | MongoDB 8.0 | Rocky Linux 9*

---

---

# Part B — Migration (MongoDB)
**Old Docker Server (Docker) → New DB Server (Binary)**

---

## Understand This Before Migrating

MongoDB migration does not have PostgreSQL's version-downgrade problem: `mongodump` and `mongorestore` are very flexible about versions. Whatever version of MongoDB you dump from, you can restore into the latest MongoDB.

The method here is:

```
mongodump (export BSON from the Old Docker Server's Docker container)
       ↓
transfer to new server
       ↓
mongorestore (restore on the New DB Server)
```

With this method:
- ✅ No data loss, as long as the app stays stopped between the final dump and the cutover
- ✅ Downtime controlled
- ✅ Rollback is easy: the old Docker server's MongoDB container is never stopped
- ✅ Version flexibility

---

## What to Do Before Migrating

### 1. Check the data size on the source

```bash
# On the old Docker server
docker exec <mongo-container-name> mongosh \
  -u admin -p <password> \
  --authenticationDatabase admin \
  --eval "db.adminCommand({ listDatabases: 1 })"
```

Note the `sizeOnDisk` of each database; it lets you estimate how long the dump and transfer will take.

### 2. Check disk space on the new server

```bash
df -h /var/backups
df -h /tmp
```

Keep at least 2 times the total size of the source databases as free space.

### 3. Test connectivity

```bash
# From the new DB server to the old Docker server
ping <combined-server-ip>

# SSH test from the old Docker server to the new server
ssh user@<new-db-server-ip> "echo 'ok'"
```

---

## Migration — Step by Step

### Overview: what you do on which server

```
Old Docker Server                    New DB Server
(running)                          (ready, but empty)
    │                                    │
    │── pre-check ──────────────────────▶│
    │                                    │
[Downtime starts]                        │
    │                                    │
    │── app containers stopped           │
    │                                    │
    │── final mongodump ────────────────▶│ (transfer)
    │                                    │
    │   DB container keeps running       │── mongorestore
    │   (for rollback)                   │
    │                                    │── data verify
    │                                    │
    │◀── backend reconnects ────────────│
    │                                    │
[Downtime ends]                          │
```

---

### Migration Step 1: Pre-Migration Dry Run (Before Downtime)

Take a test dump without stopping the app. Measure how long it takes.

```bash
# On the old Docker server
time docker exec <mongo-container-name> mongodump \
  --authenticationDatabase admin \
  -u admin \
  -p <password> \
  --out /tmp/mongo_test_dump \
  --gzip

# Check the size of the dump folder
docker exec <mongo-container-name> du -sh /tmp/mongo_test_dump

# Copy the dump out of the container
docker cp <mongo-container-name>:/tmp/mongo_test_dump /tmp/mongo_test_dump

# Test the transfer speed to the new server
time scp -r /tmp/mongo_test_dump user@<new-db-server-ip>:/tmp/mongo_test_dump
```

**Restore the test dump on the new server to check it:**

```bash
# On the new DB server
mongorestore \
  --authenticationDatabase admin \
  -u admin \
  -p <password> \
  --drop \
  --gzip \
  /tmp/mongo_test_dump

# If any error appears, look at it
# If successful, check the collection counts
```

---

### Migration Step 2: Start the Downtime Window

**Tell the application team.**

```bash
# On the old Docker server: stop only the app containers
docker stop <frontend-container-name> <backend-container-name>

# Confirm
docker ps
# Should show only the DB containers
```

Do not stop the MongoDB container; it is needed for rollback.

---

### Migration Step 3: Take the Final Dump

The app is stopped and no new writes are coming in. Take the final dump now.

```bash
# On the old Docker server

# Dump inside the container
docker exec <mongo-container-name> mongodump \
  --authenticationDatabase admin \
  -u admin \
  -p <password> \
  --out /tmp/mongo_final_$(date +%Y%m%d_%H%M%S) \
  --gzip

# Copy the dump out of the container to the host
# (note the path inside the container first)
DUMP_NAME=$(docker exec <mongo-container-name> ls /tmp | grep mongo_final | tail -1)
docker cp <mongo-container-name>:/tmp/$DUMP_NAME /tmp/$DUMP_NAME

echo "Dump ready: /tmp/$DUMP_NAME"
ls -lh /tmp/$DUMP_NAME
```

**Why `--gzip`:** the dump files are compressed, so the size drops a lot and the transfer is faster.

**What `mongodump` does:** exports every collection of every database to its own `.bson` file. Metadata (indexes, collection options) goes into separate `.json` files.

---

### Migration Step 4: Transfer the Dump

```bash
# From the old Docker server to the new DB server
scp -r /tmp/$DUMP_NAME user@<new-db-server-ip>:/tmp/

# Verify the transfer
ssh user@<new-db-server-ip> "du -sh /tmp/$DUMP_NAME"
```

The size should be the same in both places.

---

### Migration Step 5: Restore on the New Server

```bash
# On the new DB server
mongorestore \
  --authenticationDatabase admin \
  -u admin \
  -p <password> \
  --drop \
  --gzip \
  /tmp/<dump_folder_name> \
  2>&1 | tee /tmp/mongo_restore_log.txt

# Check for errors
grep -i "error\|failed" /tmp/mongo_restore_log.txt
```

**`--drop`:** drops the existing collection before restoring. The new server has no data yet, but it is still good to include; it makes the restore idempotent.

**What the restore does:** inserts documents from each `.bson` file and recreates the indexes from the `.json` files.

---

### Migration Step 6: Verify the Data

**On the new server:**

```bash
mongosh -u admin -p <password> --authenticationDatabase admin
```

```javascript
// Show all databases
show dbs

// Go into each important database
use <database_name>

// Show collections
show collections

// Check the document count of critical collections
db.<collection_name>.countDocuments()

exit
```

**Run the same counts on the old Docker server:**

```bash
docker exec <mongo-container-name> mongosh \
  -u admin -p <password> \
  --authenticationDatabase admin \
  --eval "use <database_name>; db.<collection_name>.countDocuments()"
```

If the counts match, the migration succeeded.

> **⚠️ If the counts differ:** roll back: bring the app containers up on the old Docker server again, and investigate.

---

### Migration Step 7: Reconnect the Application

Once the data is verified, tell the backend team. They will update the connection string:

```
Old: mongodb://admin:<pass>@<combined-server-ip>:27017/<dbname>?authSource=admin
New: mongodb://<app_user>:<pass>@<new-db-server-ip>:27017/<dbname>?authSource=<dbname>
```

Bring the application up and test everything: login, data reads, data writes.

If everything is fine, **the downtime is over.**

---

### Rollback Plan

If there is a problem at any step:

```bash
# On the old Docker server: bring the app up again
docker start <frontend-container-name> <backend-container-name>
```

The old Docker server's MongoDB container was never stopped. The data is intact there.

---

## Things to Know Before Migrating

- [ ] **The name of the MongoDB container on the old Docker server**: `docker ps`
- [ ] **The MongoDB admin password on the old Docker server**
- [ ] **The backend server's IP**: from the DevOps team
- [ ] **Which databases need to be migrated**: the backend team will confirm
- [ ] **When the downtime window is**: agree it with the application team
- [ ] **Who decides on rollback**: decide in advance who makes the call if something goes wrong

---

*End of MongoDB Migration section*
