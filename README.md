# Terraform AWS RDS DB Instance

Reusable Terraform module for creating **one Amazon RDS database instance**, its subnet group, and optionally a security group and an enhanced-monitoring role.

```text
        Application tier
              |
              | TCP, the engine's port
              v
   +------------------------+
   |   Security Group       |   only the sources you name
   +-----------+------------+
               |
               v
   +------------------------+
   |   RDS DB Instance      |   one engine, chosen at creation
   |   (optionally Multi-AZ)|
   +-----------+------------+
               |
               v
   +------------------------+
   |   DB Subnet Group      |   two or more subnets, two or more AZs
   +------------------------+
```

The module is intentionally focused on one responsibility: **a single DB instance**. It does not create the VPC, the subnets, the administrator's secret, or anything that runs inside the database.

---

# What an RDS instance is, and is not

This is the part that costs people the most time, so it is worth stating plainly.

**Amazon RDS is an umbrella.** Underneath it sit two different shapes of thing:

```text
Amazon RDS
│
├── DB instance                     <-- THIS MODULE
│     real engine software on one machine's storage
│     engine = postgres | mysql | mariadb | oracle-* | sqlserver-* | db2-*
│     Terraform: aws_db_instance
│
└── Aurora cluster / Multi-AZ DB cluster
      AWS's own storage layer, or three nodes with native replication
      engine = aurora-postgresql | aurora-mysql, or postgres/mysql in cluster mode
      Terraform: aws_rds_cluster + aws_rds_cluster_instance
```

AWS documentation lists Aurora among "RDS engines", which makes them look interchangeable. They are not: they are different resources with different arguments and different outputs (a cluster has a writer endpoint **and** a reader endpoint). Putting both behind one module would leave half its variables inert in either mode, so **Aurora and Multi-AZ DB clusters are not this module**.

**One engine per instance.** The engine is chosen at creation and can never be changed. You can create many *databases* inside one PostgreSQL or MySQL instance, but you cannot run PostgreSQL and MySQL on one instance. A caller needing two engines calls this module twice; `name` keeps the two identifiers apart.

**RDS is SQL only.** There is no NoSQL equivalent of RDS: DocumentDB, DynamoDB, Keyspaces and Neptune are each their own service.

---

# Multi-AZ: instance, not cluster

`multi_az = true` gives you a **Multi-AZ DB instance deployment**: one standby in a second availability zone, kept in sync, promoted automatically on failure.

```text
   multi_az = false            multi_az = true            (Multi-AZ DB CLUSTER,
                                                            a different module)
   +-----------+          +-----------+  +-----------+    +--------+ +--------+ +--------+
   | primary   |          | primary   |->| standby   |    | writer | | reader | | reader |
   |  AZ a     |          |  AZ a     |  |  AZ b     |    |  AZ a  | |  AZ b  | |  AZ c  |
   +-----------+          +-----------+  +-----------+    +--------+ +--------+ +--------+
                                          not readable      all three readable
```

**The standby serves no traffic.** You cannot connect to it, read from it, or use it in any way: it exists to fail over to. You pay for two instances and use one. If you need more read capacity, add read replicas; if you want standbys that also serve reads, you want a Multi-AZ DB cluster, which is a different resource.

Failover on a Multi-AZ DB instance typically takes about a minute.

---

# Features

* Creates a single RDS DB instance
* Supports PostgreSQL, MySQL and MariaDB
* Creates the DB subnet group
* Optionally creates a security group, with rules from security groups or CIDRs
* Optionally attaches existing security groups instead
* Supports Multi-AZ instance deployments
* Supports storage autoscaling
* Encrypts storage by default, with an optional customer-managed KMS key
* Supports gp2, gp3, io1 and io2 storage, with IOPS and throughput
* Automated backups, with configurable retention and window
* Deletion protection and a final snapshot, both on by default
* Publishes engine logs to CloudWatch
* Optional Performance Insights and enhanced monitoring, creating the monitoring role when needed
* Validates engine-specific log exports, storage combinations and Multi-AZ conflicts before the API sees them
* Accepts the administrator credential rather than owning it
* Contains no application, project or platform-specific logic

---

# Requirements

| Requirement  | Version             |
| ------------ | ------------------- |
| Terraform    | `>= 1.6.0`          |
| AWS Provider | `>= 6.0.0, < 7.0.0` |

---

# Usage

## Minimal

Everything not named here takes a default: a single-AZ `db.t4g.micro`, 20 GiB of encrypted gp3, seven days of backups, deletion protection on.

```hcl
resource "random_password" "master" {
  length           = 40
  special          = true
  override_special = "-_."
}

module "database" {
  source = "git::https://github.com/iamwonodi/terraform-aws-rds-instance.git?ref=v1.0.0"

  project_name = "acme"
  environment  = "staging"

  master_username = "acme_admin"
  master_password = random_password.master.result

  vpc_id     = module.network.vpc_id
  subnet_ids = module.network.isolated_subnet_ids

  allowed_security_group_ids = [module.network.private_security_group_id]
}
```

## Production

```hcl
module "database" {
  source = "git::https://github.com/iamwonodi/terraform-aws-rds-instance.git?ref=v1.0.0"

  project_name = "acme"
  environment  = "production"

  engine         = "postgres"
  engine_version = "16"
  instance_class = "db.m7g.large"

  master_username = "acme_admin"
  master_password = random_password.master.result

  allocated_storage     = 100
  max_allocated_storage = 1000

  multi_az                = true
  backup_retention_period = 30

  vpc_id     = module.network.vpc_id
  subnet_ids = module.network.isolated_subnet_ids

  allowed_security_group_ids = [
    module.network.private_security_group_id,
    module.network.internal_security_group_id,
  ]

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  monitoring_interval             = 60
}
```

## Two engines in one environment

An instance runs one engine, so this is two instances. `name` keeps their identifiers apart.

```hcl
module "postgres" {
  source = "git::https://github.com/iamwonodi/terraform-aws-rds-instance.git?ref=v1.0.0"

  project_name = "acme"
  environment  = "production"
  engine       = "postgres"
  # name defaults to the engine, so the identifier is acme-production-postgres
  ...
}

module "mysql" {
  source = "git::https://github.com/iamwonodi/terraform-aws-rds-instance.git?ref=v1.0.0"

  project_name = "acme"
  environment  = "production"
  engine       = "mysql"

  # MySQL and MariaDB create no database unless one is named.
  initial_database_name = "acme"
  ...
}
```

## Bringing your own security group

```hcl
module "database" {
  source = "git::https://github.com/iamwonodi/terraform-aws-rds-instance.git?ref=v1.0.0"

  create_security_group = false
  security_group_ids    = [aws_security_group.database.id]
  ...
}
```

The rules are then yours to write: `allowed_security_group_ids` and `allowed_cidr_blocks` describe rules on the group this module creates, and setting them with `create_security_group = false` fails the plan rather than silently doing nothing.

---

# The administrator credential

**The module does not generate or store it.** `master_username` and `master_password` are inputs.

This is deliberate. A module that generates a password owns it, which means the caller has to discover where it went and cannot rotate it with whatever it already uses for secrets. Generating it in the calling configuration keeps that ownership where it belongs:

```text
   your configuration                           this module
   ------------------                           -----------
   random_password.master  ------------------>  master_password
            |
            v
   your secret store (Secrets Manager,
   SSM Parameter Store, Vault, ...)
```

`manage_master_user_password`, which has RDS create and rotate a secret for you, is deliberately not used for the same reason: it creates a secret outside the caller's naming and control.

Two constraints RDS imposes, both validated here:

* 8 to 128 characters;
* no `/`, `"`, `@` or space.

Narrowing further (letters, digits and `-_.`) is worth doing if the password will travel through env files or connection strings.

---

# Deletion protection and the final snapshot

Both are **on by default**, and a `terraform destroy` therefore fails on this resource:

```text
Error: DeleteDBInstance: InvalidParameterCombination:
Cannot delete protected DB Instance, please disable deletion protection
```

That is the intended behaviour: deleting a database should take a deliberate act. To destroy one on purpose:

1. set `deletion_protection = false` and apply;
2. destroy.

The final snapshot's name defaults to `<identifier>-final-<timestamp>`, so destroying and recreating does not collide with an earlier snapshot. It is ignored in the plan, since a timestamp would otherwise change on every run.

---

# Storage

| Type | Use |
| --- | --- |
| `gp3` (default) | general-purpose SSD; `iops` and `storage_throughput` optional above the baseline |
| `gp2` | older general-purpose SSD, whose IOPS scale with size |
| `io1`, `io2` | provisioned IOPS; `iops` is required, and the module refuses the plan without it |

**Autoscaling.** `max_allocated_storage` lets RDS grow the volume as it fills. It is `0` (off) by default, because growth is billed; a production caller should set it, since a full volume stops the database.

**Encryption cannot be turned on later.** An unencrypted instance must be snapshotted, the snapshot copied with encryption, and the instance restored from the copy. The default here is `true` for that reason.

---

# Logs and monitoring

`enabled_cloudwatch_logs_exports` publishes engine logs to CloudWatch. Without it the logs stay on the instance and are lost with it. The valid names differ per engine, and a name from the wrong engine is accepted by the plan and rejected by the API, so the module checks them:

| Engine | Accepted |
| --- | --- |
| `postgres` | `postgresql`, `upgrade` |
| `mysql` | `audit`, `error`, `general`, `slowquery`, `iam-db-auth-error` |
| `mariadb` | `audit`, `error`, `general`, `slowquery` |

`monitoring_interval` turns on enhanced monitoring (operating-system metrics, not just database metrics). It needs an IAM role, which the module creates unless `monitoring_role_arn` names one.

---

# Networking

The instance goes in the subnets you give it, and `publicly_accessible` is `false` by default. Put it in private or isolated subnets: a database needs no route to the internet, and anything that reaches it should be inside the VPC.

**Two subnets minimum, in two availability zones.** RDS requires it even for a single-AZ instance, because a failover or a restore may land in another zone.

**Prefer `allowed_security_group_ids` over `allowed_cidr_blocks`.** A security group rule follows the callers as their instances are replaced; a CIDR does not.

**Ingress rules are separate resources** (`aws_vpc_security_group_ingress_rule`), not inline blocks. Inline rules replace the whole set on every change, which silently removes a rule some other configuration added.

---

# Validation

Variable-level checks live in `variables.tf`. Checks that depend on more than one variable are preconditions on the instance, so they stop the plan with a message naming the cause rather than letting the AWS API reject the apply:

```text
log exports valid for the chosen engine
max_allocated_storage greater than allocated_storage, or 0
iops set when storage_type is io1 or io2
storage_throughput only with gp3
initial_database_name set for mysql and mariadb
availability_zone not set together with multi_az
at least one security group, and rules only where the module owns the group
backups disabled only alongside a deliberate final-snapshot choice
```

They are preconditions rather than `check` blocks on purpose: a failed `check` only warns, and the apply continues.

---

# Inputs

## Required

| Name | Type | Description |
| --- | --- | --- |
| `project_name` | `string` | Part of the generated identifier |
| `environment` | `string` | Part of the generated identifier |
| `master_username` | `string` | Administrator's user name; cannot change later |
| `master_password` | `string` | Administrator's password; supplied, never generated here |
| `vpc_id` | `string` | VPC for the security group |
| `subnet_ids` | `list(string)` | At least two subnets, in two availability zones |

## Naming

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `name` | `string` | `null` | Distinguishes two instances in one environment; defaults to the engine |
| `identifier` | `string` | `null` | Overrides the generated `<project>-<environment>-<name>` |

## Engine

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `engine` | `string` | `"postgres"` | `postgres`, `mysql` or `mariadb` |
| `engine_version` | `string` | `null` | Null lets AWS choose its current default |
| `auto_minor_version_upgrade` | `bool` | `true` | Minor upgrades in the maintenance window |
| `allow_major_version_upgrade` | `bool` | `false` | Permit a major version change |
| `port` | `number` | `null` | Null uses the engine's default |
| `initial_database_name` | `string` | `null` | Required for MySQL and MariaDB |
| `parameter_group_name` | `string` | `null` | Null uses the engine's default group |
| `option_group_name` | `string` | `null` | MySQL, MariaDB and commercial engines |

## Size and storage

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `instance_class` | `string` | `"db.t4g.micro"` | |
| `allocated_storage` | `number` | `20` | GiB; 20 is the minimum |
| `max_allocated_storage` | `number` | `0` | Autoscaling ceiling; 0 disables it |
| `storage_type` | `string` | `"gp3"` | `gp2`, `gp3`, `io1`, `io2` |
| `iops` | `number` | `null` | Required for io1 and io2 |
| `storage_throughput` | `number` | `null` | gp3 only |
| `storage_encrypted` | `bool` | `true` | Cannot be turned on later |
| `kms_key_id` | `string` | `null` | Null uses the AWS-managed key |

## Availability and recovery

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `multi_az` | `bool` | `false` | A standby that serves no reads |
| `availability_zone` | `string` | `null` | Single-AZ only |
| `backup_retention_period` | `number` | `7` | Days, 0 to 35 |
| `backup_window` | `string` | `"02:00-03:00"` | UTC |
| `maintenance_window` | `string` | `"sun:03:30-sun:04:30"` | UTC |
| `deletion_protection` | `bool` | `true` | |
| `skip_final_snapshot` | `bool` | `false` | |
| `final_snapshot_identifier` | `string` | `null` | Null generates one with a timestamp |
| `copy_tags_to_snapshot` | `bool` | `true` | |
| `apply_immediately` | `bool` | `false` | Some changes restart the instance |

## Network

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `create_security_group` | `bool` | `true` | |
| `security_group_ids` | `list(string)` | `[]` | Existing groups to attach |
| `allowed_security_group_ids` | `list(string)` | `[]` | Sources allowed to the port |
| `allowed_cidr_blocks` | `list(string)` | `[]` | Sources allowed to the port |
| `publicly_accessible` | `bool` | `false` | |
| `ca_cert_identifier` | `string` | `null` | Null uses the Region's default |

## Observability

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `enabled_cloudwatch_logs_exports` | `list(string)` | `[]` | Engine-specific names |
| `performance_insights_enabled` | `bool` | `false` | |
| `performance_insights_retention_period` | `number` | `7` | 7 is free |
| `monitoring_interval` | `number` | `0` | 0, 1, 5, 10, 15, 30 or 60 |
| `monitoring_role_arn` | `string` | `null` | Null creates one when needed |
| `tags` | `map(string)` | `{}` | |

---

# Outputs

| Name | Description |
| --- | --- |
| `id` | The instance's identifier |
| `arn` | ARN of the instance |
| `resource_id` | Immutable resource ID (`db-XXXX`), which an IAM database-authentication policy names |
| `address` | Hostname clients connect to |
| `port` | Port the engine listens on |
| `endpoint` | `address:port` |
| `engine` | The engine it runs |
| `engine_version` | The exact version actually running |
| `initial_database_name` | The database created with the instance, if any |
| `master_username` | The administrator's user name; the password is not returned |
| `security_group_id` | The group this module created, or null |
| `security_group_ids` | Every group attached |
| `subnet_group_name` | Name of the DB subnet group |
| `availability_zone` | Where the instance is running |
| `multi_az` | Whether a standby exists |
| `monitoring_role_arn` | Role publishing enhanced monitoring, or null |

---

# Security Considerations

* **Not publicly accessible by default.** Put the instance in private or isolated subnets.
* **Encrypted at rest by default**, and it cannot be enabled later without a snapshot and restore.
* **Deletion protection and a final snapshot are on by default.** A destroy fails until one is turned off deliberately.
* **The administrator credential never lives in this module.** It does appear in Terraform state, as every `aws_db_instance` password does: treat the state as a secret, and keep it in an encrypted backend.
* **Traffic is not encrypted unless the client asks for it.** RDS presents a certificate, but the engines accept unencrypted connections by default; require TLS in the client (`sslmode=require` or stricter for PostgreSQL) or in a parameter group.
* **Prefer security group sources to CIDRs.** They follow the callers as instances are replaced.
* **Rotating `ca_cert_identifier` restarts the instance.** Certificates expire, so plan it into a maintenance window.

---

# Module Structure

```text
terraform-aws-rds-instance/
│
├── main.tf
├── variables.tf
├── locals.tf
├── data.tf
├── outputs.tf
├── versions.tf
├── README.md
│
└── examples/
    └── complete/
        ├── main.tf
        ├── variables.tf
        ├── outputs.tf
        └── version.tf
```

---

# Versioning

This module follows Semantic Versioning.

Current release:

```text
v1.0.0
```

The `v1.0.0` release provides:

* PostgreSQL, MySQL and MariaDB DB instances
* Multi-AZ instance deployments
* Storage autoscaling, encryption and provisioned IOPS
* Optional security group with security-group and CIDR sources
* Backups, deletion protection and final snapshots
* CloudWatch log exports, Performance Insights and enhanced monitoring
* Caller-owned administrator credential
* Multi-variable validation as plan-time preconditions

---

# License

This module is provided for reusable AWS infrastructure deployments and is intended to be consumed as a versioned Terraform module.
