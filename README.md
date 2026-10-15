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

## Como executar

1. Crie o banco PostgreSQL: `createdb mymatch`.
2. Execute `psql -d mymatch -f database/schema.sql` e, opcionalmente, `psql -d mymatch -f database/demo.sql`.
3. Exporte as variáveis de `.env.example` no ambiente (não há carregador de `.env` por decisão de não usar dependências).
4. Rode `php -S localhost:8080` na raiz e acesse `http://localhost:8080`.

Dados demonstrativos: `ana@mymatch.local` / `mymatch123`.

Para instalações já criadas antes de um incremento, aplique as novas tabelas e triggers com a ferramenta de migração escolhida pelo time; nesta fase o arquivo `database/schema.sql` representa o esquema completo de uma instalação nova.

Para habilitar a triagem administrativa em desenvolvimento, execute UPDATE users SET is_admin = true WHERE email = 'ana@mymatch.local'.

## Pagamentos

O Mercado Pago processa exclusivamente assinaturas dos usuários. O PagBank/PagSeguro processa exclusivamente pagamentos marketplace de criadores. A ativação real exige credenciais, checkout hospedado e webhook autenticado de cada provedor; planos pagos não são liberados com uma transação pendente. Para pagamentos de criador, a função de banco distribui 7% à carteira da plataforma id 1, deduz a taxa efetiva do PagSeguro e credita o restante ao criador.

## Próximos incrementos

Gate real de verificação de idade, pagamentos, upload seguro, mensageria pós-match, fila de moderação, auditoria e políticas LGPD devem ser implantados antes de produção.
