locals {
  is_localstack = var.cloud_provider == "localstack"
}

provider "aws" {
  region = var.aws_region

  # LocalStack: credenciais fictícias e validações desligadas.
  # AWS Academy: null faz o provider usar as credenciais do Learner Lab das variáveis de ambiente
  # AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY e AWS_SESSION_TOKEN.
  access_key                  = local.is_localstack ? "test" : null
  secret_key                  = local.is_localstack ? "test" : null
  s3_use_path_style           = local.is_localstack
  skip_credentials_validation = local.is_localstack
  skip_metadata_api_check     = local.is_localstack
  skip_requesting_account_id  = local.is_localstack

  # Com "aws", nenhum endpoint customizado.
  dynamic "endpoints" {
    for_each = local.is_localstack ? [var.localstack_endpoint] : []

    content {
      ec2 = endpoints.value
      rds = endpoints.value
      s3  = endpoints.value
      ssm = endpoints.value
      sts = endpoints.value
    }
  }

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
    }
  }
}
