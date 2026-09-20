locals {
  # The engine distinguishes two instances in the same environment, so a caller
  # that runs PostgreSQL and MySQL side by side needs no extra input.
  name = coalesce(var.name, var.engine)

  # RDS identifiers allow lowercase letters, digits and single hyphens, must begin
  # with a letter, and are at most 63 characters. The generated one is normalised
  # so that a project or environment containing anything else still produces a
  # valid identifier rather than an opaque API error.
  generated_identifier = substr(
    trim(
      replace(lower("${var.project_name}-${var.environment}-${local.name}"), "/[^a-z0-9]+/", "-"),
      "-",
    ),
    0,
    63,
  )

  identifier = coalesce(var.identifier, local.generated_identifier)

  default_ports = {
    postgres = 5432
    mysql    = 3306
    mariadb  = 3306
  }

  port = coalesce(var.port, local.default_ports[var.engine])

  # The snapshot's name carries a timestamp so that destroying, recreating and
  # destroying again does not collide with the first snapshot. It is read only
  # when the instance is destroyed, and ignored in the plan (see main.tf).
  final_snapshot_identifier = var.skip_final_snapshot ? null : coalesce(
    var.final_snapshot_identifier,
    "${local.identifier}-final-${formatdate("YYYYMMDDhhmmss", timestamp())}",
  )

  create_monitoring_role = var.monitoring_interval != 0 && var.monitoring_role_arn == null

  monitoring_role_arn = var.monitoring_interval == 0 ? null : coalesce(
    var.monitoring_role_arn,
    try(aws_iam_role.monitoring[0].arn, null),
  )

  security_group_ids = concat(
    var.create_security_group ? [aws_security_group.this[0].id] : [],
    var.security_group_ids,
  )

  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.tags,
  )

  # Log exports each engine accepts. A name from the wrong engine is accepted by
  # the plan and rejected by the API, so it is checked here instead.
  valid_log_exports = {
    postgres = ["postgresql", "upgrade"]
    mysql    = ["audit", "error", "general", "slowquery", "iam-db-auth-error"]
    mariadb  = ["audit", "error", "general", "slowquery"]
  }

  invalid_log_exports = [
    for export in var.enabled_cloudwatch_logs_exports : export
    if !contains(local.valid_log_exports[var.engine], export)
  ]
}
