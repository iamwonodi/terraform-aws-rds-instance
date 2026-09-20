# -----------------------------------------------------------------------------
# RDS DB Instance
# -----------------------------------------------------------------------------
# Creates one Amazon RDS database instance, its subnet group, and optionally a
# security group and an enhanced-monitoring role.
#
# A DB instance runs exactly ONE engine, chosen at creation and never changed
# afterwards. A caller needing two engines calls this module twice.
#
# This module is NOT Aurora and NOT a Multi-AZ DB cluster. Both are built from
# aws_rds_cluster, a different resource with different arguments and two
# endpoints rather than one; they belong in their own module.
#
# The administrator credential is an input. The module neither generates nor
# stores it, so the caller keeps it wherever it keeps its other secrets and this
# module never becomes the owner of one.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Subnet Group
# -----------------------------------------------------------------------------
# RDS places the instance in one of these subnets, and requires at least two
# availability zones even for a single-AZ instance: a failover or a restore may
# land in another zone.
# -----------------------------------------------------------------------------

resource "aws_db_subnet_group" "this" {
  name        = local.identifier
  description = "Subnets for ${local.identifier}."
  subnet_ids  = var.subnet_ids

  tags = merge(local.common_tags, { Name = local.identifier })
}

# -----------------------------------------------------------------------------
# Security Group
# -----------------------------------------------------------------------------
# Created unless the caller brings its own. It has no egress rules: a database
# answers connections and makes none of its own.
# -----------------------------------------------------------------------------

resource "aws_security_group" "this" {
  count = var.create_security_group ? 1 : 0

  name        = "${local.identifier}-db"
  description = "Database ${local.identifier}."
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, { Name = "${local.identifier}-db" })

  lifecycle {
    create_before_destroy = true
  }
}

# Rules are separate resources rather than inline blocks: inline rules replace
# the whole set on every change, which would drop a rule another configuration
# added.
resource "aws_vpc_security_group_ingress_rule" "from_security_group" {
  for_each = var.create_security_group ? toset(var.allowed_security_group_ids) : []

  security_group_id            = aws_security_group.this[0].id
  referenced_security_group_id = each.value

  description = "Allow ${each.value} to reach ${local.identifier}."

  ip_protocol = "tcp"
  from_port   = local.port
  to_port     = local.port

  tags = local.common_tags
}

resource "aws_vpc_security_group_ingress_rule" "from_cidr" {
  for_each = var.create_security_group ? toset(var.allowed_cidr_blocks) : []

  security_group_id = aws_security_group.this[0].id
  cidr_ipv4         = each.value

  description = "Allow ${each.value} to reach ${local.identifier}."

  ip_protocol = "tcp"
  from_port   = local.port
  to_port     = local.port

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# Enhanced Monitoring Role
# -----------------------------------------------------------------------------

resource "aws_iam_role" "monitoring" {
  count = local.create_monitoring_role ? 1 : 0

  name               = "${local.identifier}-monitoring"
  description        = "Lets RDS publish enhanced monitoring metrics for ${local.identifier}."
  assume_role_policy = data.aws_iam_policy_document.monitoring_trust[0].json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "monitoring" {
  count = local.create_monitoring_role ? 1 : 0

  role       = aws_iam_role.monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# -----------------------------------------------------------------------------
# The Instance
# -----------------------------------------------------------------------------

resource "aws_db_instance" "this" {
  identifier = local.identifier

  # ---------------------------------------------------------------------------
  # Engine
  # ---------------------------------------------------------------------------

  engine                      = var.engine
  engine_version              = var.engine_version
  auto_minor_version_upgrade  = var.auto_minor_version_upgrade
  allow_major_version_upgrade = var.allow_major_version_upgrade
  instance_class              = var.instance_class

  parameter_group_name = var.parameter_group_name
  option_group_name    = var.option_group_name

  # ---------------------------------------------------------------------------
  # Administrator
  # ---------------------------------------------------------------------------
  # Supplied by the caller. manage_master_user_password is deliberately not used:
  # it would create a secret this module does not control, which the caller then
  # has to discover rather than own.
  # ---------------------------------------------------------------------------

  username = var.master_username
  password = var.master_password

  db_name = var.initial_database_name

  # ---------------------------------------------------------------------------
  # Storage
  # ---------------------------------------------------------------------------

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage > 0 ? var.max_allocated_storage : null
  storage_type          = var.storage_type
  iops                  = var.iops
  storage_throughput    = var.storage_throughput
  storage_encrypted     = var.storage_encrypted
  kms_key_id            = var.kms_key_id

  # ---------------------------------------------------------------------------
  # Network
  # ---------------------------------------------------------------------------

  port                   = local.port
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = local.security_group_ids
  publicly_accessible    = var.publicly_accessible
  ca_cert_identifier     = var.ca_cert_identifier

  multi_az          = var.multi_az
  availability_zone = var.multi_az ? null : var.availability_zone

  # ---------------------------------------------------------------------------
  # Backups and deletion
  # ---------------------------------------------------------------------------

  backup_retention_period = var.backup_retention_period
  backup_window           = var.backup_window
  maintenance_window      = var.maintenance_window
  copy_tags_to_snapshot   = var.copy_tags_to_snapshot

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = local.final_snapshot_identifier

  # ---------------------------------------------------------------------------
  # Observability
  # ---------------------------------------------------------------------------

  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports

  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_enabled ? var.performance_insights_retention_period : null

  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = local.monitoring_role_arn

  apply_immediately = var.apply_immediately

  tags = merge(local.common_tags, { Name = local.identifier })

  # ---------------------------------------------------------------------------
  # Validation
  # ---------------------------------------------------------------------------
  # These depend on more than one variable, so they cannot live in variables.tf.
  # They are preconditions rather than check blocks: a failed check only warns
  # and lets the apply continue.
  # ---------------------------------------------------------------------------

  lifecycle {
    # The generated snapshot name contains a timestamp, which would otherwise
    # differ on every plan. It is read only when the instance is destroyed.
    ignore_changes = [final_snapshot_identifier]

    precondition {
      condition     = length(local.invalid_log_exports) == 0
      error_message = "These log exports are not valid for ${var.engine}: ${join(", ", local.invalid_log_exports)}. It accepts ${join(", ", local.valid_log_exports[var.engine])}."
    }

    precondition {
      condition     = var.max_allocated_storage == 0 || var.max_allocated_storage > var.allocated_storage
      error_message = "max_allocated_storage (${var.max_allocated_storage}) must be greater than allocated_storage (${var.allocated_storage}), or 0 to disable autoscaling."
    }

    precondition {
      condition     = !contains(["io1", "io2"], var.storage_type) || var.iops != null
      error_message = "storage_type ${var.storage_type} is provisioned IOPS, so iops must be set."
    }

    precondition {
      condition     = var.storage_throughput == null || var.storage_type == "gp3"
      error_message = "storage_throughput applies to gp3 only."
    }

    precondition {
      condition     = var.engine == "postgres" || var.initial_database_name != null
      error_message = "${var.engine} creates no database unless one is named, which would leave nothing to connect to. Set initial_database_name."
    }

    precondition {
      condition     = !var.multi_az || var.availability_zone == null
      error_message = "availability_zone pins a single-AZ instance to one zone and cannot be set when multi_az is true."
    }

    precondition {
      condition     = var.create_security_group || length(var.security_group_ids) > 0
      error_message = "create_security_group is false, so security_group_ids must name at least one existing group; an instance with none is unreachable."
    }

    precondition {
      condition     = var.create_security_group || (length(var.allowed_security_group_ids) == 0 && length(var.allowed_cidr_blocks) == 0)
      error_message = "allowed_security_group_ids and allowed_cidr_blocks describe rules on the security group this module creates, and create_security_group is false. Put the rules on the groups you supplied instead."
    }

    precondition {
      condition     = var.skip_final_snapshot || var.backup_retention_period > 0 || var.final_snapshot_identifier != null
      error_message = "Automated backups are disabled and a final snapshot is expected. That is allowed, but it means the only copy of this database is the final snapshot; set skip_final_snapshot or a retention deliberately."
    }
  }
}
