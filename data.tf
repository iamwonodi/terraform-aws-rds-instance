# -----------------------------------------------------------------------------
# Enhanced Monitoring Trust Policy
# -----------------------------------------------------------------------------
# Enhanced monitoring is collected by an agent on the instance and published by
# RDS on the caller's behalf, so RDS needs a role it can assume to do it.
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "monitoring_trust" {
  count = local.create_monitoring_role ? 1 : 0

  statement {
    sid     = "AllowRdsMonitoringToAssume"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}
