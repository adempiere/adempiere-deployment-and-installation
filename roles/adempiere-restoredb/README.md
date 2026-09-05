# adempiere-restoredb

Restores a PostgreSQL database backup into the ADempiere Docker container stack.

All database operations run inside the PostgreSQL container via `docker exec`, using Unix socket trust authentication — no TCP port needs to be open.

---

## What it does

1. Derives the dump filename from the backup filename (format auto-detected from extension).
2. Copies the backup archive from the control node to the BackEnd server.
3. Decompresses the archive if needed (skipped for uncompressed `.backup` files).
4. Drops and recreates the `adempiere` database with the correct owner.
5. Ensures the `adempiere` database user exists.
6. Restores the dump using `psql` (SQL formats) or `pg_restore` (custom format).
7. Optionally executes a post-restore SQL script.
8. Cleans up: always removes the decompressed dump file; removes the archive only if `keep_restore_file: false`.

---

## Supported backup formats

| Filename pattern | Decompress step | Restore tool |
|---|---|---|
| `*.sql.gz` | `gzip -dk` | `psql -f` |
| `*.tar.gz` | `tar -xzf` | `psql -f` |
| `*.backup.gz` | `gzip -dk` | `pg_restore -F c` |
| `*.backup` | none | `pg_restore -F c` |

The format is detected automatically from the filename extension. No variable needs to be set.

---

## Variables

All variables are set in `group_vars/all/vars.yml` and `group_vars/all/vault.yml`. None are defined in `defaults/main.yml`.

### Required

| Variable | Description |
|---|---|
| `restore_backup_filename` | Filename of the backup archive (e.g. `20260904-SAPROD.backup`) |
| `restore_local_dir` | Directory on the control node holding the backup file |
| `pg_superuser` | PostgreSQL superuser inside the container (typically `postgres`) |
| `adempiere_db` | Name of the ADempiere database (typically `adempiere`) |
| `adempiere_owner` | Owner role of the ADempiere database (typically `adempiere`) |
| `pg_container` | Docker container name for PostgreSQL (e.g. `adempiere-ui-gateway.postgresql`) |
| `install_path` | Base installation path on the server (e.g. `/opt/development`) |
| `adempiere_db_password` | *(vault)* Password for the `adempiere` database role |

### Optional

| Variable | Default | Description |
|---|---|---|
| `restore_remote_backup_dir` | `{{ install_path }}/adempiere-ui-gateway/docker-compose/postgresql/postgres_backups` | Destination directory on the server |
| `restore_container_backup_dir` | `/home/adempiere/postgres_backups` | Path inside the container (must map to `restore_remote_backup_dir`) |
| `keep_restore_file` | `true` | Keep the backup archive on the server after restore |
| `post_restore_sql_enabled` | `false` | Run a SQL script after restore |
| `post_restore_sql_filename` | — | Filename of the post-restore SQL script |
| `post_restore_sql_local_dir` | — | Directory on the control node holding the SQL script |
| `post_restore_sql_remote_dir` | `{{ install_path }}/…/03-Misc-SQLs` | Destination directory on the server for the SQL script |

---

## Usage

This role is invoked by `restore-db.sh`. Do not call it directly.

```bash
cd /data2/entwicklung/shw_repositories_2024/adempiere-deployment-and-installation_SHW
./check-config.sh restore-db   # validate before running
./restore-db.sh
```

---

## License

MIT-0
