variable "cloud_provider" {
  description = "Provedor de destino: \"localstack\" (desenvolvimento e homologação da infra) ou \"aws\" (AWS Academy)"
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

variable "project" {
  description = "Nome do projeto (tag Project e prefixo dos recursos)"
  type        = string
  default     = "oficina"
}

variable "environment" {
  description = "Nome do ambiente (tag Environment e prefixo dos recursos)"
  type        = string
  default     = "local"
}

variable "db_name" {
  description = "Nome do banco de dados"
  type        = string
  default     = "oficina"
}

variable "db_username" {
  description = "Usuário administrador do banco"
  type        = string
  default     = "oficina"
}

variable "db_instance_class" {
  description = "Classe da instância RDS"
  type        = string
  default     = "db.t3.micro"
}

variable "network_state_bucket" {
  description = "Bucket do state remoto do repositório SOAT-Oficina-Infra-K8s (o mesmo deste backend)"
  type        = string
  default     = "oficina-tfstate-local"
}

variable "network_state_key" {
  description = "Key do state do repositório SOAT-Oficina-Infra-K8s"
  type        = string
  default     = "infra-k8s/terraform.tfstate"
}
