# DevOps Assessment: Terraform + Database Reliability

A simple solution for the assessment:

- **Terraform** for AWS: `Internet → ALB → ECS Fargate → RDS PostgreSQL`, with `dev` and `prod` environments
- **Docker Compose** PostgreSQL database with migrations and seed data
- **Index** for the reporting query
- **Backup and restore** scripts
- **GitHub Actions** workflow that runs Terraform plan on pull requests

No AWS account is needed. Terraform runs in plan-only mode, and the database runs locally in Docker.

---

## Project Structure

```
.
├── infra/
│   ├── modules/
│   │   ├── network/main.tf      # VPC, public + private subnets, NAT, routes
│   │   ├── ecs/main.tf          # ALB SG, ECS SG, ALB, ECS cluster/task/service
│   │   └── rds/main.tf          # RDS SG, RDS PostgreSQL
│   └── envs/
│       ├── dev/                 # backend.tf, providers.tf, variables.tf, main.tf, terraform.tfvars
│       └── prod/                # same files, bigger sizing
├── db/migrations/
│   ├── 001_create_tables.sql
│   ├── 002_create_indexes.sql
│   └── 003_seed_data.sql
├── scripts/
│   ├── backup.sh
│   └── restore.sh
├── .github/workflows/terraform.yml
└── docker-compose.yml
```

---

## Prerequisites

- Docker with Docker Compose
- Terraform 1.6 or newer
- Bash (on Windows, use Git Bash or WSL)

---

## Part 1: Terraform Infrastructure

| Requirement | File |
|---|---|
| VPC with public and private subnets | `modules/network/main.tf` |
| ALB security group | `modules/ecs/main.tf` (`aws_security_group.alb`) |
| ECS/Fargate security group | `modules/ecs/main.tf` (`aws_security_group.ecs`) |
| RDS security group | `modules/rds/main.tf` (`aws_security_group.rds`) |
| ECS cluster, task definition, service | `modules/ecs/main.tf` |
| RDS PostgreSQL | `modules/rds/main.tf` |

**Traffic flow and security groups:**

```
Internet --80--> ALB SG --80--> ECS SG --5432--> RDS SG
```

- The ALB is in the **public** subnets and accepts HTTP from the internet.
- ECS tasks run in **private** subnets and accept traffic **only from the ALB security group**.
- RDS runs in **private** subnets with `publicly_accessible = false` and accepts port 5432 **only from the ECS security group**.
- The container is `nginx:alpine` as a placeholder.
- The RDS password is not written anywhere in the code. `manage_master_user_password = true` makes AWS generate it and store it in Secrets Manager.

---

## Part 2: Environments (dev and prod)

Each environment has its own `variables.tf`, `terraform.tfvars`, and `backend.tf` (separate state file).

| Setting | dev | prod |
|---|---|---|
| ECS task size | 256 CPU / 512 MB | 512 CPU / 1024 MB |
| ECS task count | 1 | 2 |
| RDS instance | `db.t4g.micro` | `db.t4g.medium` |
| RDS storage | 20 GB | 50 GB |
| RDS Multi-AZ | false | true |
| **RDS backup retention** | **3 days** | **14 days** |
| **RDS deletion protection** | **false** | **true** |
| State file | `dev.tfstate` | `prod.tfstate` |

The backend is **local** so `terraform init` works without AWS. Each `backend.tf` also shows the S3 backend to use in a real setup.

### Run Terraform

```bash
cd infra/envs/dev        # or infra/envs/prod
terraform fmt -check -recursive ../../
terraform init
terraform validate
terraform plan -refresh=false
```

Expected result:

```
Success! The configuration is valid.
Plan: 27 to add, 0 to change, 0 to destroy.
```

**Why it works without AWS credentials:** `providers.tf` uses dummy keys and skips AWS credential checks. To deploy for real, remove those 5 marked lines and configure real AWS credentials.

---

## Part 3: GitHub Actions (Optional Part)

`.github/workflows/terraform.yml` runs on every pull request that changes `infra/`. For both `dev` and `prod` it runs:

1. `terraform fmt -check`
2. `terraform init`
3. `terraform validate`
4. `terraform plan -refresh=false`

**Where to see the plan:**
- In the workflow run's **Summary** page
- As a downloadable **artifact** (`terraform-plan-dev`, `terraform-plan-prod`)

To test: create a branch, change anything in `infra/`, push it, and open a pull request.

---

## Part 4: Local Database

Start PostgreSQL:

```bash
docker compose up -d
docker compose ps      # wait until it shows "healthy"
```

On the first start, every file in `db/migrations/` runs automatically in order:

1. `001_create_tables.sql` creates `hotel_bookings` and `booking_events`
2. `002_create_indexes.sql` creates the indexes
3. `003_seed_data.sql` inserts the seed data

Connection details: host `localhost`, port `5432`, database `hotel`, user `app`, password `app_password`.

Check the tables:

```bash
docker compose exec db psql -U app -d hotel -c "\dt"
```

> Migration files only run when the database is empty. To start over from scratch: `docker compose down -v && docker compose up -d`

---

## Part 5: Seed Data and Indexing

### Seed data

| Requirement | Seeded |
|---|---|
| At least 100 bookings | 200 bookings |
| Multiple cities | 5 (delhi, mumbai, bangalore, goa, jaipur) |
| Multiple organizations | 3 |
| Multiple statuses | 4 (pending, confirmed, cancelled, completed) |
| Events for some bookings | 150 events (only for bookings that are not `pending`) |

Check the data:

```bash
docker compose exec db psql -U app -d hotel -c "SELECT city, status, COUNT(*) FROM hotel_bookings GROUP BY city, status ORDER BY city;"
```

### Index for the query

The query:

```sql
SELECT org_id, status, COUNT(*), SUM(amount)
FROM hotel_bookings
WHERE city = 'delhi'
  AND created_at >= NOW() - INTERVAL '30 days'
GROUP BY org_id, status;
```

The index:

```sql
CREATE INDEX idx_bookings_city_created_at
    ON hotel_bookings (city, created_at)
    INCLUDE (org_id, status, amount);
```

**Why this index:**

1. **`city` first:** the query filters with `city = 'delhi'` (an exact match), so the index jumps straight to the delhi rows.
2. **`created_at` second:** inside the delhi rows, the data is sorted by date, so only the last 30 days are read. The exact-match column must come before the range column for this to work.
3. **`INCLUDE (org_id, status, amount)`:** these are the other columns the query needs. Storing them in the index means PostgreSQL never has to read the table itself. This is called an **Index Only Scan**.

There is also an index on `booking_events(booking_id)` because PostgreSQL does not index foreign keys automatically.

### Verify the index is used

```bash
docker compose exec db psql -U app -d hotel -c "
EXPLAIN ANALYZE
SELECT org_id, status, COUNT(*), SUM(amount)
FROM hotel_bookings
WHERE city = 'delhi' AND created_at >= NOW() - INTERVAL '30 days'
GROUP BY org_id, status;"
```

Expected output contains:

```
Index Only Scan using idx_bookings_city_created_at on hotel_bookings
  Index Cond: ((city = 'delhi') AND (created_at >= (now() - '30 days')))
  Heap Fetches: 0
```

Without the index, PostgreSQL would do a `Seq Scan` (read every row in the table).

---

## Part 6: Backup and Restore

### Backup

```bash
./scripts/backup.sh
```

This creates a timestamped dump file in `backups/`, for example:

```
Backup created: backups/hotel_20261111_134756.sql
```

### Restore

```bash
./scripts/restore.sh                                  # restores the latest backup
./scripts/restore.sh backups/hotel_20261111_134756.sql  # restores a specific backup
```

The script:
1. Deletes and re-creates a **fresh** database called `hotel_restore`
2. Restores the backup into it
3. Prints row counts of the original and restored database

The original `hotel` database is never changed.

### How to verify the restore worked

**1. Compare the counts printed by the script.** They must be the same:

```
Source   (hotel):     200 bookings, 150 events
Restored (hotel_restore): 200 bookings, 150 events
Restore completed.
```

**2. Check the tables and indexes exist in the restored database:**

```bash
docker compose exec db psql -U app -d hotel_restore -c "\dt"
docker compose exec db psql -U app -d hotel_restore -c "\di"
```

**3. Run the report query on both databases.** The results must be identical:

```bash
docker compose exec db psql -U app -d hotel -c "SELECT org_id, status, COUNT(*), SUM(amount) FROM hotel_bookings WHERE city = 'delhi' AND created_at >= NOW() - INTERVAL '30 days' GROUP BY org_id, status ORDER BY 1, 2;"

docker compose exec db psql -U app -d hotel_restore -c "SELECT org_id, status, COUNT(*), SUM(amount) FROM hotel_bookings WHERE city = 'delhi' AND created_at >= NOW() - INTERVAL '30 days' GROUP BY org_id, status ORDER BY 1, 2;"
```

**4. Data-loss test (optional):** delete data, then restore it from the backup.

```bash
./scripts/backup.sh
docker compose exec db psql -U app -d hotel -c "DELETE FROM booking_events; DELETE FROM hotel_bookings;"
./scripts/restore.sh
```

The source now shows `0 bookings`, while the restored database shows `200 bookings`. The backup brought the lost data back.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| Port 5432 already in use | Change `"5432:5432"` to `"5433:5432"` in `docker-compose.yml` |
| Tables are missing | Reset the database: `docker compose down -v && docker compose up -d` |
| `Permission denied` on scripts | `chmod +x scripts/*.sh` |
| `$'\r': command not found` (Windows) | Line ending problem: `git config core.autocrlf false`, then clone again |
| `terraform fmt -check` fails | Run `terraform fmt -recursive infra` and commit |