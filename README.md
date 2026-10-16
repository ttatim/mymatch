# MyMatch

MVP web em PHP 8.3 e PostgreSQL, sem framework e sem orientação a objetos. O AdminLTE 4 local em `template/` fornece a base visual.

## Princípios implementados

- Uma conta e perfis independentes para conteúdo e relacionamentos.
- Integração opcional: visita válida + consentimento explícito + perfis ativos.
- Curtida unilateral cria apenas uma oportunidade; reciprocidade cria o match.
- Bloqueios prevalecem e invalidam interesses/matches existentes.
- Feed registra apenas acessos válidos; a identificação para integração continua dependente de consentimento.
- Denúncias são registradas para a triagem administrativa, sem expor o denunciante ao denunciado.
- Encerramento de conta interrompe novas interações, desativa os perfis e invalida matches e interesses ativos.
- Planos pagos: Relacionamentos Plus (R$ 15,90/mês) e Conteúdo Plus (R$ 59,90/mês), por cobrança recorrente exclusivamente pelo Mercado Pago.
- Marketplace de criadores: PagBank/PagSeguro é o único provedor; o ledger separa 7% para a carteira interna da plataforma (id 1), taxa administrativa do provedor e saldo do criador.
- Compra, assinatura e consumo de conteúdo não concedem acesso pessoal.
- Recuperação de senha com token de uso único, expiração de 30 minutos e resposta neutra para evitar enumeração de contas.
- MFA opcional por TOTP, segredo cifrado com Sodium e dez códigos de recuperação de uso único.

## Como executar

1. Crie o banco PostgreSQL: `createdb mymatch`.
2. Execute `psql -d mymatch -f database/schema.sql` e, opcionalmente, `psql -d mymatch -f database/demo.sql`.
3. Exporte as variáveis de `.env.example` no ambiente (não há carregador de `.env` por decisão de não usar dependências). Gere obrigatoriamente `APP_ENCRYPTION_KEY` com `php -r 'echo base64_encode(random_bytes(32)), PHP_EOL;'` antes de habilitar MFA.
4. Rode `php -S localhost:8080` na raiz e acesse `http://localhost:8080`.

Dados demonstrativos: `ana@mymatch.local` / `mymatch123`.

Para instalações já criadas antes deste incremento, aplique `database/migrations/20261015_security_access.sql`, `database/migrations/20261016_mfa_replay_protection.sql`, `database/migrations/20261016_system_secrets.sql` e `database/migrations/20261016_mistral_safety.sql`; nesta fase o arquivo `database/schema.sql` representa o esquema completo de uma instalação nova.

Para habilitar a triagem administrativa em desenvolvimento, execute UPDATE users SET is_admin = true WHERE email = 'ana@mymatch.local'.

## Segurança de acesso

O reset usa o envio de e-mail já configurado no PHP (`mail()`) e a URL de `APP_BASE_URL`; em produção, o servidor deve possuir um transporte de e-mail transacional configurado. A aplicação nunca revela se um e-mail possui conta. MFA pode ser habilitado em **Segurança de acesso** após login. Não registre, exponha em logs ou compartilhe `APP_ENCRYPTION_KEY`, chaves TOTP ou códigos de recuperação.

## Cofre de credenciais no banco

Tokens e senhas de integrações operacionais devem ser gravados na tabela `system_secrets`, sempre cifrados pela aplicação. O código os consulta sob demanda com `vault_secret('nome-do-segredo')`; não há valor em arquivo ou código-fonte. Para cadastrá-los sem expô-los na linha de comando, execute `php bin/store-secret.php <nome-do-segredo>` e forneça o valor pela entrada padrão. Exemplos: `mercadopago.access_token`, `pagseguro.webhook_token` e `mail.smtp_password`.

`DB_PASSWORD` e `APP_ENCRYPTION_KEY` são exceções técnicas necessárias: o primeiro abre a conexão com o banco e o segundo cifra os valores nele armazenados. Ambos devem ser injetados pelo ambiente seguro do provedor/KMS, nunca versionados nem inseridos na mesma base que protegem. Essa separação entre chave e dados evita que uma cópia isolada do banco revele os segredos.

## Triagem de idade e segurança com Mistral AI

Cadastre a chave como `mistral.api_key` no cofre. Publicações entram em `pending_review` e permanecem inacessíveis até a triagem. Para um item específico, execute `php bin/process-content-safety.php <content-id>`; para a fila, agende um worker restrito, por exemplo `* * * * * php /caminho/mymatch/bin/process-pending-content-safety.php 10`. O worker envia apenas imagem elegível à API Vision e aprova exclusivamente uma resposta inequívoca; sinais de menor de idade, sexualização, coerção, exploração, violência ou incerteza levam a `manual_review`.

Um administrador autorizado decide os itens bloqueados em `index.php?page=content-review`, disponível também a partir da triagem de denúncias. A abertura administrativa da mídia é gravada em auditoria. Restrinja essa função a uma equipe treinada, aplique dupla revisão para casos de alto risco e mantenha um procedimento humano de escalonamento.

O módulo inclui `mistral_ocr_document()` para documentos de verificação e a tabela `identity_verification_documents`, mas OCR/IA não constituem comprovação de maioridade nem substituem revisão humana, confirmação de identidade, política de retenção, canal de denúncia e protocolo legal de preservação/escalonamento. Não envie documentos ou mídia a provedores externos sem base legal, política de privacidade e contrato de tratamento de dados adequados.

## Implantação

Defina `APP_ENV=production`, `APP_ENCRYPTION_KEY`, `APP_BASE_URL` com HTTPS e `UPLOAD_DIRECTORY` como um diretório absoluto **fora da raiz web**, gravável apenas pelo usuário do PHP. Configure `DB_SSLMODE=require` (ou validação de certificado, quando disponível) e uma senha de banco não vazia. A aplicação recusa uploads em produção se essa configuração estiver ausente ou apontar para dentro do projeto. Execute as migrações pendentes antes de liberar tráfego e configure um transporte de e-mail transacional no PHP para a recuperação de senha.

Use `GET /health.php` para health checks do balanceador ou monitoramento. A resposta é somente `{"status":"ok"}` ou `{"status":"unavailable"}` e não expõe detalhes de conexão.

Antes de liberar tráfego, execute `php bin/preflight-production.php` no mesmo ambiente da aplicação. O comando não exibe valores secretos; ele interrompe a liberação se faltar criptografia, HTTPS, diretório privado de uploads, objetos essenciais do banco, carteira da plataforma ou os segredos necessários ao Mercado Pago.

### Contêineres

`Dockerfile` prepara Apache/PHP 8.3 com `pdo_pgsql` e bloqueia acesso direto ao diretório `storage`. Para uma prévia local completa, gere uma chave com `php -r 'echo base64_encode(random_bytes(32)), PHP_EOL;'`, substitua `APP_ENCRYPTION_KEY` em `compose.local.yml` e execute `docker compose -f compose.local.yml up --build`.

O arquivo de Compose é exclusivo para desenvolvimento: contém credenciais locais e não deve ser usado em produção. Para produção, utilize a imagem construída pelo `Dockerfile`, injete segredos pelo orquestrador, monte `UPLOAD_DIRECTORY=/var/lib/mymatch/uploads` em volume privado e conecte a um PostgreSQL gerenciado com TLS.

No macOS com Homebrew, instale e inicie PostgreSQL antes da prévia com: brew install postgresql@16; brew services start postgresql@16.

## Pagamentos

O Mercado Pago processa exclusivamente assinaturas dos usuários. O PagBank/PagSeguro processa exclusivamente pagamentos marketplace de criadores. Planos pagos usam o checkout hospedado do Mercado Pago e só são ativados após confirmação do estado remoto. Cadastre no cofre `mercadopago.access_token` e `mercadopago.webhook_secret`, então configure no painel do provedor o evento `subscription_preapproval` apontando para `https://SEU-DOMINIO/webhooks/mercadopago.php`. O endpoint valida a assinatura HMAC, limita o tempo de aceitação, deduplica o identificador de entrega e consulta novamente a assinatura no Mercado Pago antes de alterar o plano.

Para pagamentos de criador, a função de banco distribui 7% à carteira da plataforma id 1, deduz a taxa efetiva do PagSeguro e credita o restante ao criador. A ativação do marketplace PagSeguro exige o credenciamento de marketplace/split da conta da plataforma e as credenciais próprias desse contrato; até essa integração ser homologada, compras de conteúdo permanecem pendentes e não concedem acesso.

Criadores informam o identificador de marketplace PagBank em **Planos e assinaturas → Configurar recebimentos**. A operação deve validar o vínculo em index.php?page=creator-payout-review antes de ativar a conta. Publicações e compras monetizadas ficam bloqueadas enquanto o recebedor não estiver ativo.

## Próximos incrementos

Gate real de verificação de idade, pagamentos, upload seguro, mensageria pós-match, fila de moderação, auditoria e políticas LGPD devem ser implantados antes de produção.
