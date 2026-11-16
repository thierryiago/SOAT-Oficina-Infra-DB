locals {
  # Fonte única da connection string: alimenta o parâmetro do SSM e o output db_connection_string.
  db_connection_string = "Host=${aws_db_instance.main.address};Port=${aws_db_instance.main.port};Database=${aws_db_instance.main.db_name};Username=${aws_db_instance.main.username};Password=${random_password.db.result}"
}

# Lido pela Lambda (GetParameter no cold start) e pelo CD da aplicação (Secret do Kubernetes).
# Sem key_id: usa a chave gerenciada alias/aws/ssm, que dispensa CMK e key policy no AWS Academy.
# Sem overwrite (deprecado) e sem value_wo: a senha já está no state por causa do random_password.
resource "aws_ssm_parameter" "db_connection_string" {
  name        = "${var.ssm_parameter_prefix}/connection-string"
  description = "Connection string Npgsql do banco da Oficina (usuario mestre)"
  type        = "SecureString"
  value       = local.db_connection_string
}
