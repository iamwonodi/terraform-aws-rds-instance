# -----------------------------------------------------------------------------
# Connection
# -----------------------------------------------------------------------------

output "address" {
  description = "Hostname clients connect to."
  value       = module.database.address
}

output "port" {
  description = "Port the engine listens on."
  value       = module.database.port
}

output "endpoint" {
  description = "Hostname and port together."
  value       = module.database.endpoint
}

# -----------------------------------------------------------------------------
# Identity
# -----------------------------------------------------------------------------

output "identifier" {
  description = "The instance's identifier."
  value       = module.database.id
}

output "arn" {
  description = "ARN of the instance."
  value       = module.database.arn
}

# -----------------------------------------------------------------------------
# Credential
# -----------------------------------------------------------------------------

output "admin_secret_arn" {
  description = "ARN of the secret holding the administrator credential. The credential belongs to this configuration, not to the module."
  value       = aws_secretsmanager_secret.master.arn
}

# -----------------------------------------------------------------------------
# Network
# -----------------------------------------------------------------------------

output "security_group_id" {
  description = "The security group the module created for the database."
  value       = module.database.security_group_id
}
