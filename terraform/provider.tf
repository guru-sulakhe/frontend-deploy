terraform {
  required_providers { # providers helps in that we are using aws in the terraform, thus providers are essential in terraform
    aws = {
      source = "hashicorp/aws"
      version = "5.64.0"
    }
  }
  backend "s3" {
    bucket = "guru97s-remote-state"
    key    = "expense-infra-dev-frontend-server"
    region = "us-east-1"
    dynamodb_table = "guru97s-locking-dynamodb"
  }
}
# by including backend s3 terraform will create .state file in s3-bucket of AWS
# backend "s3" of bucket is used to manage state files
# dynamodb_table is used to maintain .lock file for the state files in s3 bucket

# provide authentication here
# before running the .tf file please ensure of the $ aws configre for authentication.
# by usign below provider, terraform will authenticate to aws by the region, because using aws CLI for authentication at which we mentioned region aslo
provider "aws" {
  region = "us-east-1"
}