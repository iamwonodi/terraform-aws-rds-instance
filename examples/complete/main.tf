# -----------------------------------------------------------------------------
# Complete Example
# -----------------------------------------------------------------------------
# Shows the module as a production caller would use it:
#
#   - the administrator password generated and stored by the CALLER, since the
#     module neither generates nor stores one;
#   - storage encrypted and autoscaling, backups kept, deletion protected;
#   - reachable only from the security groups named, on the engine's port;
#   - engine logs published to CloudWatch.
#
# It creates a real RDS instance, which costs money. Destroying it needs
# deletion_protection cleared first, which is the point of that default.
# -----------------------------------------------------------------------------

provider "aws" {
  region = var.aws_region
}

# -----------------------------------------------------------------------------
# The administrator credential
# -----------------------------------------------------------------------------
# RDS rejects /, " and @ in a password, and a value that travels through env
# files and connection strings is easier to handle without other punctuation, so
# the alphabet is narrowed rather than left to chance.
# -----------------------------------------------------------------------------

resource "random_password" "master" {
  length           = 40
  special          = true
  override_special = "-_."
}

resource "aws_secretsmanager_secret" "master" {
  name        = "${var.project_name}-${var.environment}-database-admin"
  description = "Administrator credential for the ${var.project_name} ${var.environment} database."
}

resource "aws_secretsmanager_secret_version" "master" {
  secret_id = aws_secretsmanager_secret.master.id

  secret_string = jsonencode({
    username = local.master_username
    password = random_password.master.result
    engine   = "postgres"
    host     = module.database.address
    port     = module.database.port
  })
}

locals {
  master_username = "${replace(var.project_name, "-", "_")}_admin"
}

# -----------------------------------------------------------------------------
# The database
# -----------------------------------------------------------------------------

module "database" {
  source = "../../"

  project_name = var.project_name
  environment  = var.environment

  engine         = "postgres"
  engine_version = "16"
  instance_class = "db.t4g.medium"

  master_username = local.master_username
  master_password = random_password.master.result

  allocated_storage     = 50
  max_allocated_storage = 500
  storage_type          = "gp3"
  storage_encrypted     = true

  multi_az = true

  backup_retention_period = 30
  backup_window           = "02:00-03:00"
  maintenance_window      = "sun:03:30-sun:04:30"

  deletion_protection = true
  skip_final_snapshot = false

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  allowed_security_group_ids = var.allowed_security_group_ids

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  monitoring_interval = 60

  tags = {
    Component = "Database"
  }
}
