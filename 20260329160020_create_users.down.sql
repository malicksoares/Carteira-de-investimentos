# Carteira de Investimentos — Rust Fullstack

Aplicação fullstack em **Rust** para cadastrar, acompanhar e acompanhar o valor de ativos
de investimento (ações, criptomoedas, renda fixa etc.), desenvolvida a partir do desafio
[DIO — Carteira de Investimentos em Rust](https://github.com/digitalinnovationone/rust-fullstack-carteira-investimentos).

## O que o projeto faz

- Permite que qualquer pessoa **crie uma conta** e **faça login** de forma segura.
- Cada pessoa usuária tem a **sua própria carteira**: os ativos cadastrados por um usuário
  não aparecem para outro.
- Para cada ativo é possível informar **nome, categoria, quantidade e valor unitário**.
- O **dashboard** mostra a lista de ativos e o **valor total investido** (quantidade × valor
  unitário, somado entre todos os ativos).
- É possível **criar, editar e excluir** ativos tanto pela interface web (HTML) quanto por uma
  **API JSON** autenticada.
- A sessão é mantida por meio de um **cookie HTTP-only** contendo um **JWT**.

## Tecnologias usadas

| Camada            | Tecnologia                                              |
| ----------------- | -------------------------------------------------------- |
| Linguagem         | Rust (edition 2024)                                       |
| Web framework     | [Axum](https://github.com/tokio-rs/axum) 0.8              |
| Banco de dados    | PostgreSQL 18 (via Docker)                                 |
| Acesso a dados    | [SQLx](https://github.com/launchbadge/sqlx) (queries verificadas em tempo de compilação) |
| Templates HTML    | [Askama](https://github.com/askama-rs/askama)              |
| Autenticação      | JWT ([jwt-simple](https://crates.io/crates/jwt-simple)) + cookie assinado, senha com hash ([password-auth](https://crates.io/crates/password-auth)) |
| Erros             | [thiserror](https://crates.io/crates/thiserror) + [color-eyre](https://crates.io/crates/color-eyre) |
| Testes            | [sqlx::test](https://docs.rs/sqlx/latest/sqlx/attr.test.html) + [insta](https://insta.rs/) (snapshot testing) |
| Runtime assíncrono | [Tokio](https://tokio.rs/)                                |

## Estrutura do projeto

```
src/
├── app.rs              # bootstrap da aplicação (router, listener, config)
├── auth/
│   └── user.rs          # UnauthenticatedUser, User, geração/validação de JWT
├── error.rs             # AppError e conversão para respostas HTTP
├── models.rs             # Asset, UserRecord
├── repository.rs          # acesso ao PostgreSQL via SQLx
├── routes/
│   ├── api.rs            # API JSON (/api/assets), protegida por JWT
│   └── frontend.rs        # páginas HTML (dashboard, login, cadastro, forms)
├── main.rs
migrations/                # migrations SQLx (versionadas e incrementais)
templates/                  # templates Askama (HTML)
```

## Como executar a aplicação

### Pré-requisitos

- [Rust](https://www.rust-lang.org/tools/install) (edition 2024 — use a toolchain estável mais
  recente, `rustup update`)
- [Docker](https://www.docker.com/) e Docker Compose, para subir o PostgreSQL
- [sqlx-cli](https://crates.io/crates/sqlx-cli), para rodar as migrations:
  ```bash
  cargo install sqlx-cli --no-default-features --features postgres
  ```

### Passo a passo

1. **Clone o repositório e configure as variáveis de ambiente:**

   ```bash
   git clone <url-do-seu-fork>
   cd rust-fullstack-carteira-investimentos
   cp .env.example .env
   ```

   Edite o `.env` e defina um `JWT_SECRET` próprio (qualquer string longa e aleatória serve
   para desenvolvimento local).

2. **Suba o banco de dados:**

   ```bash
   docker compose up -d
   ```

3. **Rode as migrations:**

   ```bash
   sqlx migrate run
   ```

4. **Rode a aplicação:**

   ```bash
   cargo run
   ```

5. Acesse **http://localhost:3000** no navegador. Você será redirecionado para a tela de
   login; clique em "Cadastre-se" para criar sua primeira conta.

> A porta pode ser alterada definindo a variável `PORT` no `.env` (padrão: `3000`).

## Melhorias implementadas em relação ao projeto base

O repositório base já trazia a fundação (Axum + SQLx + Askama + JWT em cookie, CRUD de ativos
e uma tela de login simples). A partir dela, evoluí o projeto com:

1. **Carteira por pessoa usuária** — os ativos agora pertencem a quem os cadastrou
   (`assets.user_id`), em vez de serem uma lista global compartilhada por todo mundo.
2. **Quantidade e categoria dos ativos** — além do valor unitário, cada ativo tem uma
   `quantity` e uma `category`, permitindo registros mais realistas (ex.: "10 ações da
   Petrobras", "0.05 Bitcoin").
3. **Cálculo do valor total da carteira** — o dashboard soma `quantidade × valor unitário`
   de todos os ativos e exibe o total investido.
4. **Dashboard de verdade** — a antiga página que só exibia "Hello, usuário" virou uma tela
   com tabela de ativos, valor total e ações de editar/excluir.
5. **Formulários HTML para criar e editar ativos** — antes só existia a API JSON; agora dá
   para gerenciar a carteira inteira pelo navegador, sem precisar de `curl`/Postman.
6. **Exclusão de ativos**, que não existia no projeto base (só havia criar/listar/atualizar).
7. **Cadastro e login separados** — no projeto base, um login com usuário inexistente criava
   a conta automaticamente. Agora existem uma tela de **cadastro** e uma de **login**
   distintas, com validação de tamanho mínimo de usuário/senha e mensagens de erro amigáveis
   (sem revelar se o problema foi o usuário ou a senha, por segurança).
8. **Logout**, removendo o cookie de sessão.
9. **JWT_SECRET configurável por variável de ambiente**, em vez de uma chave fixa no código-fonte
   — muito mais seguro para qualquer ambiente que não seja "brincar localmente".
10. **Sessão mais longa (2 horas)** em vez de 10 minutos, evitando deslogar o usuário no meio
    do uso do dashboard.
11. **Remoção do "modo admin"** — como cada pessoa agora só mexe na própria carteira, o
    cabeçalho de admin fixo (`im-the-admin`) que liberava criar/editar ativos deixou de fazer
    sentido e foi removido em favor da autenticação normal por usuário.
12. **Validações e mensagens de erro mais claras** — nome obrigatório, quantidade e valor
    unitário não podem ser negativos, nome de ativo duplicado na mesma carteira é rejeitado
    com mensagem específica, tudo em português.
13. **Endpoint de exclusão na API** (`DELETE /api/assets/{id}`), além de criação/listagem/edição.
14. **`.env.example` versionado** em vez de um `.env` com segredo comitado, seguindo boas
    práticas de segurança.
15. **Novos testes** cobrindo criação, listagem, atualização, exclusão e rejeição de
    quantidade negativa.

## Como testar sua versão

### Testes automatizados

Com o banco de dados rodando (`docker compose up -d`) e a variável `DATABASE_URL` definida,
rode:

```bash
cargo test
```

Os testes usam `sqlx::test`, que cria um banco de dados temporário para cada teste, aplica as
migrations automaticamente e roda o teste isolado — não é preciso preparar nada manualmente.

Alguns testes usam snapshots (`insta`). Na primeira execução após uma mudança de schema, é
esperado que os snapshots antigos não batham; para revisar e aceitar os novos, use:

```bash
cargo install cargo-insta
cargo insta review
```

### Teste manual pela interface web

1. Acesse `/register` e crie uma conta.
2. Cadastre alguns ativos em `/assets/new` (ex.: "Tesouro Selic", categoria "Renda Fixa",
   quantidade `1`, valor unitário `1500.00`).
3. Confira o dashboard (`/`): o valor total deve refletir a soma de todos os ativos.
4. Edite um ativo e confirme que o total é recalculado.
5. Exclua um ativo e confirme que ele some da lista e do total.
6. Clique em "sair" e confirme que você é redirecionado para o login e não consegue mais
   acessar `/` sem autenticar novamente.

### Teste manual da API

Depois de logado pelo navegador, o cookie `token` fica disponível para o próprio navegador.
Para testar a API isoladamente com `curl`, primeiro faça login e capture o cookie:

```bash
curl -i -c cookies.txt -X POST http://localhost:3000/login \
  -d "username=trader&password=minhasenha123"

curl -b cookies.txt http://localhost:3000/api/assets

curl -b cookies.txt -X POST http://localhost:3000/api/assets \
  -H "Content-Type: application/json" \
  -d '{"name": "Bitcoin", "category": "Cripto", "quantity": 0.1, "unit_value": 350000}'

curl -b cookies.txt -X PATCH http://localhost:3000/api/assets/1 \
  -H "Content-Type: application/json" \
  -d '{"quantity": 0.2}'

curl -b cookies.txt -X DELETE http://localhost:3000/api/assets/1
```

## O que eu aprendi durante o desafio

- Como estruturar um projeto Axum em módulos coesos (rotas, autenticação, acesso a dados,
  erros), usando **extractors customizados** (`FromRequestParts`) para injetar `User` e
  `Repository` diretamente nos handlers, sem boilerplate espalhado pelo código.
- Como o `sqlx::query_as!` verifica as consultas SQL **em tempo de compilação**, o que pega
  erros de schema muito antes de qualquer teste rodar — e como isso muda a forma de pensar
  migrations (elas viram parte do contrato do código, não só do banco).
- Como modelar autenticação com **JWT em cookie HTTP-only**, incluindo os cuidados para não
  vazar informação sensível nas mensagens de erro (ex.: não dizer se foi o usuário ou a senha
  que estava errada).
- Como o Askama aproxima a escrita de templates HTML da escrita de código Rust "de verdade":
  os erros de template (variável que não existe, tipo errado) aparecem como **erros de
  compilação**, não como página quebrada em produção.
- A importância de pensar em **modelagem multiusuário desde a base** — o projeto original
  tratava os ativos como uma lista global, e adaptar isso para "cada usuário tem sua própria
  carteira" tocou o banco, o repositório, as rotas e os testes ao mesmo tempo, o que reforçou
  como uma decisão de modelagem simples no início evita retrabalho grande depois.
- Como equilibrar validação no back-end (que é a que realmente protege os dados) com
  validação simples no HTML (`required`, `min`, `minlength`) para dar feedback mais rápido
  para quem está usando o formulário.

## Possíveis próximos passos

- Paginação e busca na lista de ativos.
- Histórico de preços por ativo, com gráfico de evolução da carteira ao longo do tempo.
- Exportação da carteira em CSV/PDF.
- Rate limiting no login para mitigar tentativas de força bruta.
- Refresh token / renovação de sessão sem precisar logar novamente a cada 2 horas.
