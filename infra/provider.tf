terraform {
  cloud {
    organization = "Terraform-nauka"
    workspaces {
      name = "stock-market-realtime-pipeline"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
