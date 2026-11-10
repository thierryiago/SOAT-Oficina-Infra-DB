resource "random_password" "db" {
  length  = 24
  special = false # o RDS rejeita "/", "@", "\"" e espaço na senha mestre
}

resource "aws_db_subnet_group" "main" {
  name       = "${local.name}-db"
  subnet_ids = local.private_subnet_ids

  tags = {
    Name = "${local.name}-db"
  }
}

resource "aws_security_group" "db" {
  name        = "${local.name}-db"
  description = "Security group do banco, acessivel apenas pelo cluster e pelos clientes autorizados"
  vpc_id      = local.vpc_id

  ingress {
    description     = "PostgreSQL a partir do security group do cluster"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [local.cluster_security_group_id]
  }

  ingress {
    description     = "PostgreSQL a partir dos clientes autorizados"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.db_clients.id]
  }

  tags = {
    Name = "${local.name}-db"
  }
}

# Anexado pelos consumidores fora do cluster (a Lambda de autenticação) para alcançar o banco.
# Fica neste repositório para a Lambda depender só do state do banco, sem dependência circular.
# O egress vai para o CIDR da VPC, e não para o SG do banco, para os dois SGs não se referenciarem.
resource "aws_security_group" "db_clients" {
  name        = "${local.name}-db-clients"
  description = "Clientes autorizados a acessar o banco (ex.: Lambda de autenticacao)"
  vpc_id      = local.vpc_id

  egress {
    description = "PostgreSQL dentro da VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.network.cidr_block]
  }

  tags = {
    Name = "${local.name}-db-clients"
  }
}

resource "aws_db_instance" "main" {
  identifier = "${local.name}-db"

  engine         = "postgres"
  engine_version = "16"
  instance_class = var.db_instance_class

  allocated_storage = 20
  storage_type      = "gp3"

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false

  # Permite o destroy depois de cada demo no AWS Academy.
  skip_final_snapshot = true
  deletion_protection = false
}
