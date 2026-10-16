-- Cofre de credenciais operacionais: os valores são cifrados pela aplicação antes de serem gravados.
CREATE TABLE system_secrets (
  name VARCHAR(100) PRIMARY KEY,
  ciphertext TEXT NOT NULL,
  version INTEGER NOT NULL DEFAULT 1 CHECK (version > 0),
  is_active BOOLEAN NOT NULL DEFAULT true,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
