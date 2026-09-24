# A fresh environment: the callers' security groups are created in the same
# apply as the database, so their IDs are unknown when the plan is made.
# terraform_data stands in for them.
resource "terraform_data" "caller" {
  input = "caller"
}

module "under_test" {
  source = "../.."

  project_name    = "acme"
  environment     = "staging"
  name            = "postgres"
  engine          = "postgres"
  master_username = "platformadmin"
  master_password = "S3cret-pw.x-long-enough"
  vpc_id          = "vpc-0abc"
  subnet_ids      = ["subnet-0a", "subnet-0b"]

  allowed_security_group_ids = [terraform_data.caller.id, "sg-0existing"]
}
