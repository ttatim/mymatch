# MyMatch

MVP web em PHP 8.3 e PostgreSQL, sem framework e sem orientação a objetos. O AdminLTE 4 local em `template/` fornece a base visual.

## Princípios implementados

- Uma conta e perfis independentes para conteúdo e relacionamentos.
- Integração opcional: visita válida + consentimento explícito + perfis ativos.
- Curtida unilateral cria apenas uma oportunidade; reciprocidade cria o match.
- Bloqueios prevalecem e invalidam interesses/matches existentes.
- Compra, assinatura e consumo de conteúdo não concedem acesso pessoal.

## Como executar

1. Crie o banco PostgreSQL: `createdb mymatch`.
2. Execute `psql -d mymatch -f database/schema.sql` e, opcionalmente, `psql -d mymatch -f database/demo.sql`.
3. Exporte as variáveis de `.env.example` no ambiente (não há carregador de `.env` por decisão de não usar dependências).
4. Rode `php -S localhost:8080` na raiz e acesse `http://localhost:8080`.

Dados demonstrativos: `ana@mymatch.local` / `mymatch123`.

## Próximos incrementos

Gate real de verificação de idade, pagamentos, upload seguro, mensageria pós-match, fila de moderação, auditoria e políticas LGPD devem ser implantados antes de produção.
