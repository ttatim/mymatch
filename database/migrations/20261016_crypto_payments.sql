ALTER TYPE payment_provider ADD VALUE IF NOT EXISTS 'bitcoin';
ALTER TYPE payment_provider ADD VALUE IF NOT EXISTS 'ethereum';
ALTER TABLE payment_transactions DROP CONSTRAINT payment_transactions_check;
ALTER TABLE payment_transactions ADD CONSTRAINT payment_transactions_context_provider_check CHECK (
  (context = 'subscription' AND subscription_id IS NOT NULL AND provider IN ('mercadopago','bitcoin','ethereum'))
  OR (context = 'marketplace' AND subscription_id IS NULL AND provider = 'pagseguro')
);
CREATE TABLE crypto_wallet_addresses (
  asset payment_provider PRIMARY KEY CHECK (asset IN ('bitcoin','ethereum')),
  address VARCHAR(160) NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT true,
  updated_by BIGINT REFERENCES users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE crypto_payment_requests (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  transaction_id BIGINT NOT NULL UNIQUE REFERENCES payment_transactions(id) ON DELETE CASCADE,
  asset payment_provider NOT NULL CHECK (asset IN ('bitcoin','ethereum')),
  destination_address VARCHAR(160) NOT NULL,
  transaction_hash VARCHAR(130) UNIQUE,
  status VARCHAR(20) NOT NULL DEFAULT 'awaiting_payment' CHECK (status IN ('awaiting_payment','submitted','confirmed','rejected','expired')),
  reviewed_by BIGINT REFERENCES users(id),
  submitted_at TIMESTAMPTZ,
  reviewed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX crypto_payment_requests_review ON crypto_payment_requests(status,created_at);
