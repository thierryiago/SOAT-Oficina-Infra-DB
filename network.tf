# A rede pertence ao repositório SOAT-Oficina-Infra-K8s. Contrato consumido (outputs daquele state):
# vpc_id, private_subnet_ids e cluster_security_group_id.
data "terraform_remote_state" "network" {
  backend = "s3"

  # Com "aws", os atributos null ficam sem valor e as credenciais vêm das variáveis de ambiente.
  config = {
    bucket = var.network_state_bucket
    key    = var.network_state_key
    region = var.aws_region

    endpoints                   = local.is_localstack ? { s3 = var.localstack_endpoint } : null
    access_key                  = local.is_localstack ? "test" : null
    secret_key                  = local.is_localstack ? "test" : null
    use_path_style              = local.is_localstack
    skip_credentials_validation = local.is_localstack
    skip_metadata_api_check     = local.is_localstack
    skip_requesting_account_id  = local.is_localstack
    skip_region_validation      = local.is_localstack
  }
}

data "aws_vpc" "network" {
  id = local.vpc_id
}

locals {
  name = "${var.project}-${var.environment}"

  vpc_id                    = data.terraform_remote_state.network.outputs.vpc_id
  private_subnet_ids        = data.terraform_remote_state.network.outputs.private_subnet_ids
  cluster_security_group_id = data.terraform_remote_state.network.outputs.cluster_security_group_id
}
