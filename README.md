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

Para instalações já criadas antes deste incremento, aplique `database/migrations/20261015_security_access.sql`; nesta fase o arquivo `database/schema.sql` representa o esquema completo de uma instalação nova.

Para habilitar a triagem administrativa em desenvolvimento, execute UPDATE users SET is_admin = true WHERE email = 'ana@mymatch.local'.

## Segurança de acesso

O reset usa o envio de e-mail já configurado no PHP (`mail()`) e a URL de `APP_BASE_URL`; em produção, o servidor deve possuir um transporte de e-mail transacional configurado. A aplicação nunca revela se um e-mail possui conta. MFA pode ser habilitado em **Segurança de acesso** após login. Não registre, exponha em logs ou compartilhe `APP_ENCRYPTION_KEY`, chaves TOTP ou códigos de recuperação.

## Implantação

Defina `APP_ENV=production`, `APP_ENCRYPTION_KEY`, `APP_BASE_URL` com HTTPS e `UPLOAD_DIRECTORY` como um diretório absoluto **fora da raiz web**, gravável apenas pelo usuário do PHP. Configure `DB_SSLMODE=require` (ou validação de certificado, quando disponível) e uma senha de banco não vazia. A aplicação recusa uploads em produção se essa configuração estiver ausente ou apontar para dentro do projeto. Execute as migrações pendentes antes de liberar tráfego e configure um transporte de e-mail transacional no PHP para a recuperação de senha.

Use `GET /health.php` para health checks do balanceador ou monitoramento. A resposta é somente `{"status":"ok"}` ou `{"status":"unavailable"}` e não expõe detalhes de conexão.

No macOS com Homebrew, instale e inicie PostgreSQL antes da prévia com: brew install postgresql@16; brew services start postgresql@16.

## Pagamentos

O Mercado Pago processa exclusivamente assinaturas dos usuários. O PagBank/PagSeguro processa exclusivamente pagamentos marketplace de criadores. A ativação real exige credenciais, checkout hospedado e webhook autenticado de cada provedor; planos pagos não são liberados com uma transação pendente. Para pagamentos de criador, a função de banco distribui 7% à carteira da plataforma id 1, deduz a taxa efetiva do PagSeguro e credita o restante ao criador.

## Próximos incrementos

Gate real de verificação de idade, pagamentos, upload seguro, mensageria pós-match, fila de moderação, auditoria e políticas LGPD devem ser implantados antes de produção.
