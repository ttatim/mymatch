CREATE TABLE creator_payment_accounts (
  user_id BIGINT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  provider payment_provider NOT NULL CHECK (provider = 'pagseguro'),
  provider_account_id VARCHAR(160) NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','active','rejected')),
  reviewed_by BIGINT REFERENCES users(id),
  submitted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  reviewed_at TIMESTAMPTZ,
  UNIQUE(provider,provider_account_id)
);
