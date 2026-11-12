terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.69"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
  }

  # Configuração parcial: o bucket e o endpoint mudam por provedor e um bloco backend não aceita variáveis.
  # terraform init -backend-config=backend/localstack.s3.tfbackend   (ou backend/aws.s3.tfbackend)
  backend "s3" {}
}
