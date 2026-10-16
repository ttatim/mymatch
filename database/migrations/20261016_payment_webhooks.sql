CREATE TABLE webhook_events (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  provider payment_provider NOT NULL,
  request_id VARCHAR(255) NOT NULL,
  resource_id VARCHAR(255) NOT NULL,
  received_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  processed_at TIMESTAMPTZ,
  UNIQUE(provider,request_id)
);
