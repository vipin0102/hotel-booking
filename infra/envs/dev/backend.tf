# Separate state file for DEV.
# Local backend so `terraform init` works without AWS.
# For real use, switch to S3:
#   backend "s3" {
#     bucket = "hotel-terraform-state"
#     key    = "dev/terraform.tfstate"
#     region = "ap-south-1"
#   }
terraform {
  backend "local" {
    path = "dev.tfstate"
  }
}
