-- Aplicar uma única vez em instalações existentes, antes de habilitar MFA ou recuperação de senha.
CREATE TABLE password_reset_tokens (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash CHAR(64) NOT NULL UNIQUE,
  expires_at TIMESTAMPTZ NOT NULL,
  used_at TIMESTAMPTZ,
  requested_ip INET,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX password_reset_tokens_lookup ON password_reset_tokens (user_id, expires_at DESC) WHERE used_at IS NULL;

CREATE TABLE mfa_totp (
  user_id BIGINT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  secret_ciphertext TEXT NOT NULL,
  is_enabled BOOLEAN NOT NULL DEFAULT false,
  last_used_step BIGINT,
  enabled_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE mfa_recovery_codes (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  code_hash VARCHAR(255) NOT NULL,
  used_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX mfa_recovery_codes_available ON mfa_recovery_codes(user_id) WHERE used_at IS NULL;

CREATE TABLE auth_throttles (
  scope VARCHAR(40) NOT NULL,
  subject_hash CHAR(64) NOT NULL,
  attempts SMALLINT NOT NULL DEFAULT 0,
  window_started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  locked_until TIMESTAMPTZ,
  PRIMARY KEY (scope, subject_hash)
);
