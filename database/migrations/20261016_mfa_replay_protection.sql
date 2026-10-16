-- Aplicar em bancos que já receberam a migração de segurança de acesso.
ALTER TABLE mfa_totp ADD COLUMN IF NOT EXISTS last_used_step BIGINT;
