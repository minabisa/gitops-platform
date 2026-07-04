terraform {
  required_version = ">= 1.5.0"

  backend "s3" {
    bucket       = "gitops-platform-tfstate-928535088615"
    key          = "dev/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = local.tags
  }
}

locals {
  project     = "gitops-platform"
  environment = "dev"
  tags = {
    Project     = "gitops-platform"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

module "vpc" {
  source      = "../../modules/vpc"
  project     = local.project
  environment = local.environment
  vpc_cidr    = "10.0.0.0/16"
  tags        = local.tags
}

module "ecr" {
  source      = "../../modules/ecr"
  project     = local.project
  environment = local.environment
  tags        = local.tags
}

module "eks" {
  source             = "../../modules/eks"
  project            = local.project
  environment        = local.environment
  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids
  node_instance_type = "t3.small"
  node_desired       = 1
  node_min           = 1
  node_max           = 2
  tags               = local.tags
}
