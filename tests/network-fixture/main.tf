# Fixture de rede: substitui o SOAT-Oficina-Infra-K8s no CI e nas validações isoladas do banco.
# Grava na key infra-k8s/terraform.tfstate os mesmos outputs que o repositório de rede expõe
# (vpc_id, private_subnet_ids e cluster_security_group_id). Nunca use num ambiente com a rede real:
# os dois gravariam na mesma key.
#
# terraform init -backend-config=../../backend/localstack.s3.tfbackend -backend-config="key=infra-k8s/terraform.tfstate"

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.69"
    }
  }

  backend "s3" {}
}

variable "cloud_provider" {
  description = "Provedor de destino: \"localstack\" ou \"aws\""
  type        = string
  default     = "localstack"

  validation {
    condition     = contains(["localstack", "aws"], var.cloud_provider)
    error_message = "cloud_provider deve ser \"localstack\" ou \"aws\"."
  }
}

variable "localstack_endpoint" {
  description = "Endpoint do LocalStack (ignorado com cloud_provider = \"aws\")"
  type        = string
  default     = "http://localhost:4566"
}

variable "aws_region" {
  description = "Região AWS"
  type        = string
  default     = "us-east-1"
}

locals {
  is_localstack = var.cloud_provider == "localstack"
  name          = "oficina-fixture"
}

provider "aws" {
  region = var.aws_region

  access_key                  = local.is_localstack ? "test" : null
  secret_key                  = local.is_localstack ? "test" : null
  skip_credentials_validation = local.is_localstack
  skip_metadata_api_check     = local.is_localstack
  skip_requesting_account_id  = local.is_localstack

  dynamic "endpoints" {
    for_each = local.is_localstack ? [var.localstack_endpoint] : []

    content {
      ec2 = endpoints.value
      sts = endpoints.value
    }
  }

  default_tags {
    tags = {
      Project = "oficina"
      Purpose = "network-fixture"
    }
  }
}

# O subnet group do RDS exige subnets em pelo menos duas zonas.
data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.99.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = local.name
  }
}

resource "aws_subnet" "private" {
  count = 2

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${local.name}-private-${count.index}"
  }
}

# Faz o papel do security group do cluster EKS: é a origem liberada na porta 5432 do banco.
resource "aws_security_group" "cluster" {
  name        = "${local.name}-cluster"
  description = "Substituto do SG do cluster para testes do banco"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.name}-cluster"
  }
}

output "vpc_id" {
  description = "ID da VPC da fixture"
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "IDs das subnets privadas da fixture"
  value       = aws_subnet.private[*].id
}

output "cluster_security_group_id" {
  description = "ID do SG que substitui o do cluster"
  value       = aws_security_group.cluster.id
}
