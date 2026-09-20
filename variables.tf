# -----------------------------------------------------------------------------
# Naming
# -----------------------------------------------------------------------------

variable "project_name" {
  type        = string
  description = "Project the instance belongs to. Part of its identifier."

  validation {
    condition     = trimspace(var.project_name) != ""
    error_message = "project_name must not be empty."
  }
}

variable "environment" {
  type        = string
  description = "Environment the instance belongs to. Part of its identifier."

  validation {
    condition     = trimspace(var.environment) != ""
    error_message = "environment must not be empty."
  }
}

variable "name" {
  type        = string
  default     = null
  description = "Distinguishes this instance from another in the same project and environment. Defaults to the engine, so two instances with different engines never collide. Set it when an environment runs two instances of the same engine."

  validation {
    condition     = var.name == null || can(regex("^[a-z0-9][a-z0-9-]*$", coalesce(var.name, "x")))
    error_message = "name must be lowercase letters, digits and hyphens, starting with a letter or digit."
  }
}

variable "identifier" {
  type        = string
  default     = null
  description = "The instance's identifier, overriding the generated <project>-<environment>-<name>. AWS allows 1-63 characters: lowercase letters, digits and hyphens, beginning with a letter, with no two hyphens together and no trailing hyphen."

  validation {
    condition     = var.identifier == null || can(regex("^[a-z][a-z0-9]*(-[a-z0-9]+)*$", coalesce(var.identifier, "x")))
    error_message = "identifier must begin with a letter and contain only lowercase letters, digits and single hyphens."
  }

  validation {
    condition     = var.identifier == null || length(coalesce(var.identifier, "x")) <= 63
    error_message = "identifier must be at most 63 characters."
  }
}

# -----------------------------------------------------------------------------
# Engine
#
# A DB instance runs exactly ONE engine, chosen at creation and never changed.
# An environment needing two engines creates two instances.
# -----------------------------------------------------------------------------

variable "engine" {
  type        = string
  default     = "postgres"
  description = "Database engine: postgres, mysql or mariadb."

  validation {
    condition     = contains(["postgres", "mysql", "mariadb"], var.engine)
    error_message = "engine must be postgres, mysql or mariadb. RDS also offers Oracle, SQL Server and Db2; those need licensing and option groups this module does not cover."
  }
}

variable "engine_version" {
  type        = string
  default     = null
  description = "Engine version, for example \"16\" or \"16.4\". Null lets AWS choose its current default for the engine. Pin it once a project depends on a version's behaviour."
}

variable "auto_minor_version_upgrade" {
  type        = bool
  default     = true
  description = "Apply minor engine upgrades during the maintenance window. Minor releases are where security fixes arrive."
}

variable "allow_major_version_upgrade" {
  type        = bool
  default     = false
  description = "Permit a change of engine_version across a major version. Major upgrades can be one-way and may need parameter-group changes, so this is deliberate."
}

variable "port" {
  type        = number
  default     = null
  description = "Port the engine listens on. Null uses the engine's default: 5432 for PostgreSQL, 3306 for MySQL and MariaDB."

  validation {
    condition     = var.port == null || (coalesce(var.port, 5432) >= 1150 && coalesce(var.port, 5432) <= 65535)
    error_message = "port must be between 1150 and 65535, the range RDS accepts."
  }
}

variable "initial_database_name" {
  type        = string
  default     = null
  description = "A database created with the instance. PostgreSQL always has one called \"postgres\", so this is usually left null there. MySQL and MariaDB have none unless this is set, which leaves nothing to connect to."

  validation {
    condition     = var.initial_database_name == null || can(regex("^[A-Za-z_][A-Za-z0-9_]*$", coalesce(var.initial_database_name, "x")))
    error_message = "initial_database_name must be a plain identifier: a letter or underscore, then letters, digits and underscores."
  }
}

variable "parameter_group_name" {
  type        = string
  default     = null
  description = "An existing DB parameter group. Null uses the engine's default group, whose parameters cannot be changed."
}

variable "option_group_name" {
  type        = string
  default     = null
  description = "An existing DB option group. Only MySQL, MariaDB and the commercial engines use these."
}

# -----------------------------------------------------------------------------
# Administrator credential
#
# The module does NOT generate or store these. The caller owns the credential,
# so it can be generated, stored and rotated by whatever the project already
# uses for secrets, and this module never becomes the owner of one.
# -----------------------------------------------------------------------------

variable "master_username" {
  type        = string
  description = "The administrator's user name. It cannot be changed after creation, and the engines reserve some names (\"admin\", \"rdsadmin\", \"postgres\" among them)."

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9_]{0,62}$", var.master_username))
    error_message = "master_username must begin with a letter and contain only letters, digits and underscores."
  }

  validation {
    condition     = !contains(["admin", "rdsadmin", "postgres", "root", "guest", "public"], lower(var.master_username))
    error_message = "master_username must not be a name the engines reserve: admin, rdsadmin, postgres, root, guest or public."
  }
}

variable "master_password" {
  type        = string
  sensitive   = true
  description = "The administrator's password. Generate and store it in the calling configuration; this module only passes it to RDS. RDS requires 8 to 128 characters and forbids /, \" and @."

  validation {
    condition     = length(var.master_password) >= 8 && length(var.master_password) <= 128
    error_message = "master_password must be between 8 and 128 characters."
  }

  validation {
    condition     = !can(regex("[/\"@ ]", var.master_password))
    error_message = "master_password must not contain a slash, a double quote, an at sign or a space: RDS rejects them."
  }
}

# -----------------------------------------------------------------------------
# Size and storage
# -----------------------------------------------------------------------------

variable "instance_class" {
  type        = string
  default     = "db.t4g.micro"
  description = "Instance class. The default is the smallest useful one; a production caller overrides it."

  validation {
    condition     = can(regex("^db\\.[a-z0-9]+\\.[a-z0-9]+$", var.instance_class))
    error_message = "instance_class must look like db.t4g.micro."
  }
}

variable "allocated_storage" {
  type        = number
  default     = 20
  description = "Storage in GiB. 20 is the minimum for gp2 and gp3."

  validation {
    condition     = var.allocated_storage >= 20 && var.allocated_storage <= 65536
    error_message = "allocated_storage must be between 20 and 65536 GiB."
  }
}

variable "max_allocated_storage" {
  type        = number
  default     = 0
  description = "Upper bound for storage autoscaling, which RDS applies as the volume fills. 0 disables autoscaling, and a full volume then stops the database. When set it must exceed allocated_storage."
}

variable "storage_type" {
  type        = string
  default     = "gp3"
  description = "Storage type: gp2 or gp3 for general-purpose SSD, io1 or io2 for provisioned IOPS."

  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2"], var.storage_type)
    error_message = "storage_type must be gp2, gp3, io1 or io2."
  }
}

variable "iops" {
  type        = number
  default     = null
  description = "Provisioned IOPS. Required for io1 and io2; optional for gp3 above the volume's baseline."
}

variable "storage_throughput" {
  type        = number
  default     = null
  description = "Storage throughput in MiB/s. gp3 only."
}

variable "storage_encrypted" {
  type        = bool
  default     = true
  description = "Encrypt storage at rest. It cannot be turned on later: an unencrypted instance must be snapshotted, the snapshot copied with encryption, and the instance restored from it."
}

variable "kms_key_id" {
  type        = string
  default     = null
  description = "KMS key for storage encryption. Null uses the AWS-managed RDS key."
}

# -----------------------------------------------------------------------------
# Availability and recovery
# -----------------------------------------------------------------------------

variable "multi_az" {
  type        = bool
  default     = false
  description = "Run a standby in a second availability zone. The standby serves no reads: it exists to fail over to, and doubles the instance cost. (A Multi-AZ DB CLUSTER, with two readable standbys, is a different resource and is not this module.)"
}

variable "availability_zone" {
  type        = string
  default     = null
  description = "Pin a single-AZ instance to one zone. Must be null when multi_az is true."
}

variable "backup_retention_period" {
  type        = number
  default     = 7
  description = "Days of automated backups, 0 to 35. 0 disables them, which also disables point-in-time recovery."

  validation {
    condition     = var.backup_retention_period >= 0 && var.backup_retention_period <= 35
    error_message = "backup_retention_period must be between 0 and 35."
  }
}

variable "backup_window" {
  type        = string
  default     = "02:00-03:00"
  description = "Daily backup window, UTC, as hh:mm-hh:mm. It must not overlap maintenance_window."

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]-([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_window))
    error_message = "backup_window must look like 02:00-03:00."
  }
}

variable "maintenance_window" {
  type        = string
  default     = "sun:03:30-sun:04:30"
  description = "Weekly maintenance window, UTC, as ddd:hh:mm-ddd:hh:mm."

  validation {
    condition     = can(regex("^(mon|tue|wed|thu|fri|sat|sun):([01][0-9]|2[0-3]):[0-5][0-9]-(mon|tue|wed|thu|fri|sat|sun):([01][0-9]|2[0-3]):[0-5][0-9]$", var.maintenance_window))
    error_message = "maintenance_window must look like sun:03:30-sun:04:30, with lowercase day names."
  }
}

variable "deletion_protection" {
  type        = bool
  default     = true
  description = "Refuse to delete the instance while set. A destroy then fails on this resource until someone clears it deliberately, which is the point of it."
}

variable "skip_final_snapshot" {
  type        = bool
  default     = false
  description = "Delete without a final snapshot. False by default: a deleted database with no snapshot cannot be recovered."
}

variable "final_snapshot_identifier" {
  type        = string
  default     = null
  description = "Name for the final snapshot. Null generates <identifier>-final-<timestamp>, so a second destroy never collides with the first snapshot."
}

variable "copy_tags_to_snapshot" {
  type        = bool
  default     = true
  description = "Put the instance's tags on its snapshots, so a snapshot can still be attributed months later."
}

variable "apply_immediately" {
  type        = bool
  default     = false
  description = "Apply changes at once rather than in the maintenance window. Some changes restart the instance."
}

# -----------------------------------------------------------------------------
# Network
# -----------------------------------------------------------------------------

variable "vpc_id" {
  type        = string
  description = "VPC the instance lives in. Used for the security group this module creates."

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a VPC ID (vpc-...)."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnets for the DB subnet group. RDS requires at least two availability zones even for a single-AZ instance, because a failover or a restore may land in another."

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "subnet_ids must contain at least two subnets, in different availability zones."
  }
}

variable "create_security_group" {
  type        = bool
  default     = true
  description = "Create a security group for the instance. Set false to attach existing ones through security_group_ids."
}

variable "security_group_ids" {
  type        = list(string)
  default     = []
  description = "Existing security groups to attach, in addition to the one this module creates (if any)."
}

variable "allowed_security_group_ids" {
  type        = list(string)
  default     = []
  description = "Security groups allowed to reach the instance's port. Preferred over CIDRs: it follows the callers as their instances change."
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  default     = []
  description = "IPv4 CIDR blocks allowed to reach the instance's port. Use only where a security group cannot express the source."
}

variable "publicly_accessible" {
  type        = bool
  default     = false
  description = "Give the instance a public address. False by default; a database reachable from the internet is an unusual thing to want."
}

variable "ca_cert_identifier" {
  type        = string
  default     = null
  description = "Certificate authority for the instance's TLS certificate, for example rds-ca-rsa2048-g1. Null uses the Region's current default. Certificates expire, and rotating one restarts the instance."
}

# -----------------------------------------------------------------------------
# Observability
# -----------------------------------------------------------------------------

variable "enabled_cloudwatch_logs_exports" {
  type        = list(string)
  default     = []
  description = "Engine logs to publish to CloudWatch. Without them the logs stay on the instance and are lost with it. PostgreSQL accepts [\"postgresql\", \"upgrade\"]; MySQL and MariaDB accept [\"audit\", \"error\", \"general\", \"slowquery\"]."
}

variable "performance_insights_enabled" {
  type        = bool
  default     = false
  description = "Performance Insights. Note that AWS has announced the end of its free console experience; CloudWatch Database Insights is the successor."
}

variable "performance_insights_retention_period" {
  type        = number
  default     = 7
  description = "Days of Performance Insights data. 7 is free; anything longer is billed."
}

variable "monitoring_interval" {
  type        = number
  default     = 0
  description = "Seconds between enhanced monitoring samples: 0, 1, 5, 10, 15, 30 or 60. 0 disables it. Anything else creates an IAM role and carries a CloudWatch cost."

  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "monitoring_interval must be 0, 1, 5, 10, 15, 30 or 60."
  }
}

variable "monitoring_role_arn" {
  type        = string
  default     = null
  description = "An existing role for enhanced monitoring. Null creates one when monitoring_interval is not 0."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to every resource this module creates."
}
