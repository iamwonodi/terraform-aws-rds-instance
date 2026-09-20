# -----------------------------------------------------------------------------
# Instance
# -----------------------------------------------------------------------------

output "id" {
  description = "The instance's identifier."
  value       = aws_db_instance.this.identifier
}

output "arn" {
  description = "ARN of the instance."
  value       = aws_db_instance.this.arn
}

output "resource_id" {
  description = "The instance's immutable resource ID (db-XXXX). It survives a rename, and is what an IAM database-authentication policy names."
  value       = aws_db_instance.this.resource_id
}

# -----------------------------------------------------------------------------
# Connection
# -----------------------------------------------------------------------------

output "address" {
  description = "Hostname clients connect to."
  value       = aws_db_instance.this.address
}

output "port" {
  description = "Port the engine listens on."
  value       = aws_db_instance.this.port
}

output "endpoint" {
  description = "Hostname and port together, as address:port."
  value       = aws_db_instance.this.endpoint
}

output "engine" {
  description = "The engine this instance runs. An instance runs exactly one."
  value       = aws_db_instance.this.engine
}

output "engine_version" {
  description = "The engine version actually running, which is the exact minor version even when only a major one was asked for."
  value       = aws_db_instance.this.engine_version_actual
}

output "initial_database_name" {
  description = "The database created with the instance, if any."
  value       = aws_db_instance.this.db_name
}

output "master_username" {
  description = "The administrator's user name. The password is the caller's and is not returned."
  value       = aws_db_instance.this.username
}

# -----------------------------------------------------------------------------
# Network
# -----------------------------------------------------------------------------

output "security_group_id" {
  description = "The security group this module created, or null when the caller supplied its own."
  value       = var.create_security_group ? aws_security_group.this[0].id : null
}

output "security_group_ids" {
  description = "Every security group attached to the instance."
  value       = local.security_group_ids
}

output "subnet_group_name" {
  description = "Name of the DB subnet group."
  value       = aws_db_subnet_group.this.name
}

output "availability_zone" {
  description = "The zone the instance is running in."
  value       = aws_db_instance.this.availability_zone
}

output "multi_az" {
  description = "Whether a standby is running in a second availability zone."
  value       = aws_db_instance.this.multi_az
}

# -----------------------------------------------------------------------------
# Monitoring
# -----------------------------------------------------------------------------

output "monitoring_role_arn" {
  description = "Role RDS uses to publish enhanced monitoring, whether created here or supplied. Null when monitoring is off."
  value       = local.monitoring_role_arn
}
