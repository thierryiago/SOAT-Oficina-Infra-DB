# SOAT-Oficina-Infra-DB

Terraform do banco PostgreSQL gerenciado (RDS) da Oficina, Tech Challenge SOAT Fase 3.

Este repositório cria apenas o banco. A rede (VPC, subnets e o security group do cluster) pertence ao [SOAT-Oficina-Infra-K8s](https://github.com/thierryiago/SOAT-Oficina-Infra-K8s) e é lida por `terraform_remote_state`. Dockerfile não se aplica: aqui não há aplicação, só infraestrutura.

> README mínimo da RDS-1. A versão completa, com as decisões de modelagem e o fluxo de CI/CD, é a RDS-5.

## O que é criado

| Recurso | Detalhe |
|---|---|
| `aws_db_instance.main` | PostgreSQL 16, `db.t3.micro`, 20 GB `gp3`, sem acesso público, `skip_final_snapshot = true` e `deletion_protection = false` (destroy liberado no AWS Academy) |
| `aws_db_subnet_group.main` | Subnets privadas da rede |
| `aws_security_group.db` | Libera a porta 5432 só para o SG do cluster e para o SG `db-clients` |
| `aws_security_group.db_clients` | Para os clientes fora do cluster (a Lambda de autenticação); egress 5432 para a VPC |
| `random_password.db` | Senha mestre, guardada só no state (bucket privado e versionado) |

## Pré-requisitos

- Terraform `>= 1.10`.
- O bucket de state criado pelo bootstrap do SOAT-Oficina-Infra-K8s.
- A rede já aplicada, com state em `infra-k8s/terraform.tfstate` no mesmo bucket.
- **LocalStack:** container em `http://localhost:4566`, publicando a faixa `4510-4559` (porta do Postgres), com `LOCALSTACK_AUTH_TOKEN`.
- **AWS Academy:** Learner Lab iniciado e as variáveis `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` e `AWS_SESSION_TOKEN` exportadas. Elas expiram a cada ~4h; confira com `aws sts get-caller-identity`.

## Como usar

O provedor é escolhido pela variável `cloud_provider` (`localstack` | `aws`) do `terraform.tfvars`. O backend usa configuração parcial, porque o bucket muda por provedor.

```bash
cp terraform.tfvars.example terraform.tfvars        # escolha um dos cenários

# LocalStack
terraform init -backend-config=backend/localstack.s3.tfbackend

# AWS Academy
cp backend/aws.s3.tfbackend.example backend/aws.s3.tfbackend   # informe o bucket
terraform init -backend-config=backend/aws.s3.tfbackend -reconfigure

terraform plan
terraform apply
terraform output -raw db_connection_string        # sensível: não cole em logs
terraform destroy
```

O state fica na key `infra-db/terraform.tfstate`, com `use_lockfile = true`. `terraform.tfvars` e `backend/aws.s3.tfbackend` não são versionados. O `.terraform.lock.hcl` é versionado.

Validação sem backend nem credenciais (a mesma do CI):

```bash
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
```

## Contrato entre repositórios

**Consumido** do state `infra-k8s/terraform.tfstate`:

| Output | Uso |
|---|---|
| `vpc_id` | VPC dos security groups |
| `private_subnet_ids` | Subnet group do banco |
| `cluster_security_group_id` | Origem liberada na porta 5432 |

> ⚠️ Na AWS real, os nodes de um managed node group recebem o security group **gerenciado pelo EKS** (`aws_eks_cluster.main.vpc_config[0].cluster_security_group_id`), não o SG adicional passado em `vpc_config`. O `cluster_security_group_id` precisa ser esse SG gerenciado; senão os pods não alcançam o banco na AWS (no LocalStack os SGs não filtram tráfego, então não se nota a diferença).

**Produzido** (lido pela Lambda e pela aplicação):

| Output | Sensível |
|---|---|
| `db_endpoint`, `db_port`, `db_name`, `db_username`, `db_password`, `db_connection_string` (Npgsql) | sim |
| `db_security_group_id` | não |
| `db_client_security_group_id`: anexar à Lambda para acessar o banco | não |

## IAM

Este repositório não cria nem usa IAM roles: o RDS não precisa delas sem o Enhanced Monitoring (avaliado na RDS-3). Por isso a restrição do AWS Academy (usar o `LabRole`) não se aplica aqui.

## Notas do LocalStack

- O Postgres roda dentro do container do LocalStack, numa porta da faixa `4510-4559` (veja `terraform output -raw db_port`).
- As regras dos SGs são inline. Com `aws_vpc_security_group_*_rule`, o LocalStack devolve o SG referenciado com prefixo da conta e sem `description`, e todo `plan` mostrava mudanças.
