terraform {
  required_version = ">=1.5.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "<= 5.76"
    }
  }
}

provider "aws" {
  region = "us-west-2"
  default_tags {
    tags = local.tags
  }
}
