# SOAT-Oficina-Infra-DB

Terraform do banco PostgreSQL gerenciado (RDS) da Oficina, Tech Challenge SOAT Fase 3.

Este repositório cria o banco e publica a connection string no SSM Parameter Store. A rede (VPC, subnets e o security group do cluster) pertence ao [SOAT-Oficina-Infra-K8s](https://github.com/thierryiago/SOAT-Oficina-Infra-K8s) e é lida por `terraform_remote_state`. Dockerfile não se aplica: aqui não há aplicação, só infraestrutura.

> README mínimo da RDS-1. A versão completa, com as decisões de modelagem e o fluxo de CI/CD, é a RDS-5.

## O que é criado

| Recurso | Detalhe |
|---|---|
| `aws_db_instance.main` | PostgreSQL 16, `db.t3.micro`, 20 GB `gp3`, sem acesso público, `skip_final_snapshot = true` e `deletion_protection = false` (destroy liberado no AWS Academy) |
| `aws_db_subnet_group.main` | Subnets privadas da rede |
| `aws_security_group.db` | Libera a porta 5432 só para o SG do cluster e para o SG `db-clients` |
| `aws_security_group.db_clients` | Para os clientes fora do cluster (a Lambda de autenticação); egress 5432 para a VPC |
| `random_password.db` | Senha mestre, guardada só no state (bucket privado e versionado) |
| `aws_ssm_parameter.db_connection_string` | `SecureString` em `/oficina/db/connection-string` (prefixo em `ssm_parameter_prefix`), cifrado com a chave gerenciada `alias/aws/ssm`, tier `Standard` |

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
| `db_connection_string_parameter_name`: nome do parâmetro (`/oficina/db/connection-string`) | não |
| `db_connection_string_parameter_arn`: ARN do parâmetro, para a permissão de leitura | não |

E o parâmetro `SecureString` `/oficina/db/connection-string` (chave `alias/aws/ssm`), com o mesmo valor do output `db_connection_string`: os dois vêm do mesmo `local`.

## Entrega das credenciais

Nenhuma senha passa por variáveis, `secrets` ou `vars` de CI. Este repositório só **publica** o parâmetro; a leitura é implementada em cada consumidor, seguindo este contrato:

| Consumidor | Como lê | Onde é implementado |
|---|---|---|
| **Lambda de autenticação** | Recebe só o **nome** do parâmetro na variável `DB_CONNECTION_STRING_PARAMETER` e faz `GetParameter` com `WithDecryption = true` no cold start, com cache em campo estático. A permissão vem do `LabRole` (AWS Academy) ou da role criada pelo Terraform da Lambda (LocalStack), com `ssm:GetParameter` e `kms:Decrypt` restritos ao ARN do output `db_connection_string_parameter_arn`. | [LAMBDA-4](https://github.com/thierryiago/SOAT-Oficina-Lambda-Auth/issues/4) |
| **CD da aplicação** | Lê o parâmetro com `aws ssm get-parameter --with-decryption`, aplica `::add-mask::` no valor e cria o Secret `oficina-secrets` com `kubectl create secret ... --dry-run=client -o yaml \| kubectl apply -f -`. A senha passa pela memória do runner, mas nunca por `secrets`/`vars` do GitHub. | [PIPE-2](https://github.com/thierryiago/SOAT-Fase-1-Lil-Golden-Hammer/issues/180) |

Leitura manual (o valor é sensível, não cole em logs):

```bash
aws ssm get-parameter --name /oficina/db/connection-string --with-decryption   --query Parameter.Value --output text
```

**Rotação:** se a senha mudar (`random_password` recriado), o mesmo `apply` atualiza o parâmetro. Os consumidores leem de novo no próximo deploy ou cold start.

> ⚠️ **Rota da Lambda até o SSM.** A Lambda roda nas subnets privadas, e a rede não tem NAT Gateway nem VPC endpoint. Na AWS, o `GetParameter` em runtime fica **sem rota** até uma destas saídas, que não pertencem a este repositório:
> - **(a) Recomendado:** VPC interface endpoint `com.amazonaws.<região>.ssm` nas subnets privadas ([INFRA-4](https://github.com/thierryiago/SOAT-Oficina-Infra-K8s/issues/4)), com SG liberando 443 a partir do SG `db-clients`.
> - **(b)** NAT Gateway: funciona, mas custa mais e consome o crédito do Academy.
> - **(c)** A Lambda lê o parâmetro no deploy (`data "aws_ssm_parameter"`) e recebe o valor como variável de ambiente. Dispensa a rota, mas a senha aparece na configuração da function e no state dela.
>
> No LocalStack os SGs e as rotas não filtram tráfego, então a diferença não aparece lá.

### Plano B: SSM bloqueado no Learner Lab

O uso do SSM no AWS Academy ainda será confirmado pelo spike da INFRA-2. Se o `PutParameter` ou o `GetParameter` for negado:

- **Este repositório:** o plano B fica só documentado. Comprovado o bloqueio, o parâmetro passa a ser condicional (ex.: `var.publish_ssm_parameter` com `count`). O output `db_connection_string` continua existindo justamente para isso.
- **Lambda:** lê `db_connection_string` do `terraform_remote_state` deste repositório (ela já depende dele por causa do SG `db-clients`) e recebe o valor como variável de ambiente.
- **CD da aplicação:** roda `terraform output -raw db_connection_string` sobre o state remoto, com as credenciais do Learner Lab.

Nos dois casos a senha continua fora de `secrets`/`vars` de CI.

## Usuário somente leitura

A Lambda só faz um `SELECT` parametrizado em `Customers`, então um role `oficina_readonly` com `GRANT SELECT` seria o ideal de menor privilégio. **Decisão: não criar nesta fase.** A Lambda usa o usuário mestre, pelo parâmetro acima.

- **O Terraform não alcança o banco na AWS.** O provider `cyrilgdn/postgresql` precisa de conexão direta com a instância, que é privada, e o runner de CI está fora da VPC (sem bastion e sem NAT). Funcionaria só no LocalStack, quebrando a paridade entre provedores.
- **O `GRANT` depende das tabelas,** criadas pelas migrations da aplicação. O lugar natural é o Job de migrations, ou seja, trabalho no repositório da aplicação.
- **Mitigações em vigor:** banco privado, porta 5432 liberada só para o SG do cluster e o `db-clients`, query parametrizada e credencial fora do Git e do CI.

**Caminho de evolução:**

1. Este repositório gera um `random_password.db_readonly` e publica `/oficina/db/readonly-connection-string` (`SecureString`).
2. O Job de migrations, depois do `migrate`, roda um script idempotente: `CREATE ROLE oficina_readonly LOGIN PASSWORD ...` (se não existir), `GRANT CONNECT ON DATABASE oficina`, `GRANT USAGE ON SCHEMA public`, `GRANT SELECT ON "Customers"` e `ALTER DEFAULT PRIVILEGES`.
3. A Lambda troca só o nome do parâmetro em `DB_CONNECTION_STRING_PARAMETER`.

## IAM

Este repositório não cria nem usa IAM roles: o RDS não precisa delas sem o Enhanced Monitoring (avaliado na RDS-3). Por isso a restrição do AWS Academy (usar o `LabRole`) não se aplica aqui.

## Notas do LocalStack

- O Postgres roda dentro do container do LocalStack, numa porta da faixa `4510-4559` (veja `terraform output -raw db_port`).
- O host da connection string (no output e no parâmetro do SSM) é `localhost`, o do LocalStack visto da máquina. Consumidores em container trocam o host (ex.: `host.k3d.internal`), como faz o `k8s/scripts/create-secrets.ps1` da Fase 2.
- O LocalStack não cifra o `SecureString` de fato: o `get-parameter` **sem** `--with-decryption` também devolve o texto puro. Na AWS, sem a flag, vem o valor cifrado. O tipo (`SecureString`) e a chave (`alias/aws/ssm`) são registrados normalmente.
- No Git Bash, use `MSYS_NO_PATHCONV=1` ao passar `--name /oficina/...` para o `aws`; senão o nome vira um caminho do Windows.
- As regras dos SGs são inline. Com `aws_vpc_security_group_*_rule`, o LocalStack devolve o SG referenciado com prefixo da conta e sem `description`, e todo `plan` mostrava mudanças.
