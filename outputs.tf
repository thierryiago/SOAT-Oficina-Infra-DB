output "db_endpoint" {
  description = "Endereço do banco (host)"
  value       = aws_db_instance.main.address
  sensitive   = true
}

output "db_port" {
  description = "Porta do banco"
  value       = aws_db_instance.main.port
  sensitive   = true
}

output "db_name" {
  description = "Nome do banco"
  value       = aws_db_instance.main.db_name
  sensitive   = true
}

output "db_username" {
  description = "Usuário do banco"
  value       = aws_db_instance.main.username
  sensitive   = true
}

output "db_password" {
  description = "Senha do banco"
  value       = random_password.db.result
  sensitive   = true
}

output "db_connection_string" {
  description = "Connection string no formato Npgsql"
  value       = local.db_connection_string
  sensitive   = true
}

output "db_connection_string_parameter_name" {
  description = "Nome do parâmetro SecureString do SSM com a connection string (lido pela Lambda e pelo CD)"
  value       = aws_ssm_parameter.db_connection_string.name
}

output "db_connection_string_parameter_arn" {
  description = "ARN do parâmetro SecureString do SSM com a connection string (permissão de leitura da Lambda)"
  value       = aws_ssm_parameter.db_connection_string.arn
}

output "db_security_group_id" {
  description = "ID do security group do banco"
  value       = aws_security_group.db.id
}

output "db_client_security_group_id" {
  description = "ID do security group a anexar aos clientes do banco fora do cluster (Lambda)"
  value       = aws_security_group.db_clients.id
}
