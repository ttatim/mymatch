-- MyMatch: PostgreSQL 16+. As regras críticas são reforçadas também na camada PHP.
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE TYPE account_status AS ENUM ('active', 'suspended', 'closed');
CREATE TYPE access_kind AS ENUM ('free', 'single_purchase', 'subscription');
CREATE TYPE interest_origin AS ENUM ('discovery', 'content_visit');
CREATE TYPE interest_status AS ENUM ('pending', 'accepted', 'dismissed', 'invalidated', 'expired');
CREATE TYPE match_status AS ENUM ('active', 'unmatched', 'blocked');
CREATE TYPE plan_code AS ENUM ('relationship_free', 'content_free', 'relationship_plus', 'content_plus', 'creator');
CREATE TYPE subscription_status AS ENUM ('pending', 'active', 'past_due', 'cancelled');
CREATE TYPE payment_provider AS ENUM ('pagseguro', 'mercadopago');
CREATE TYPE payment_status AS ENUM ('pending', 'approved', 'rejected', 'refunded');
CREATE TYPE payment_context AS ENUM ('subscription', 'marketplace');

CREATE TABLE users (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  email VARCHAR(254) NOT NULL UNIQUE,
  password_hash VARCHAR(255) NOT NULL,
  birth_date DATE NOT NULL,
  is_admin BOOLEAN NOT NULL DEFAULT false,
  status account_status NOT NULL DEFAULT 'active',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (birth_date <= CURRENT_DATE - INTERVAL '18 years')
);
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
CREATE TABLE system_secrets (
  name VARCHAR(100) PRIMARY KEY,
  ciphertext TEXT NOT NULL,
  version INTEGER NOT NULL DEFAULT 1 CHECK (version > 0),
  is_active BOOLEAN NOT NULL DEFAULT true,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE user_settings (
  user_id BIGINT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  content_enabled BOOLEAN NOT NULL DEFAULT false,
  dating_enabled BOOLEAN NOT NULL DEFAULT false,
  integration_enabled BOOLEAN NOT NULL DEFAULT false,
  visitor_identity_consent BOOLEAN NOT NULL DEFAULT false,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (NOT integration_enabled OR dating_enabled)
);
CREATE TABLE plans (
  code plan_code PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  monthly_price_cents INTEGER NOT NULL DEFAULT 0 CHECK (monthly_price_cents >= 0),
  description TEXT NOT NULL,
  is_public BOOLEAN NOT NULL DEFAULT true
);
CREATE TABLE account_plans (
  user_id BIGINT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  plan plan_code NOT NULL REFERENCES plans(code),
  activated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
INSERT INTO plans (code,name,monthly_price_cents,description) VALUES
  ('relationship_free','Relacionamentos gratuito',0,'Acesso de relacionamento gratuito conforme regras de descoberta disponíveis.'),
  ('content_free','Conteúdo gratuito',0,'Rede social de conteúdo: até 10 publicações por mês e perfis públicos.'),
  ('relationship_plus','Relacionamentos Plus',1590,'Perfis, fotos, match e conversas por cobrança mensal recorrente.'),
  ('content_plus','Conteúdo Plus',5990,'Acesso pago à plataforma de conteúdo por cobrança mensal recorrente.'),
  ('creator','Criador de conteúdo',0,'Monetização definida pelo criador, com divisão de marketplace.');
CREATE TABLE subscriptions (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id),
  plan plan_code NOT NULL REFERENCES plans(code),
  provider payment_provider,
  provider_subscription_id VARCHAR(255) UNIQUE,
  status subscription_status NOT NULL DEFAULT 'pending',
  started_at TIMESTAMPTZ, renews_at TIMESTAMPTZ, cancelled_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX subscriptions_one_active_plan ON subscriptions(user_id, plan) WHERE status IN ('pending','active','past_due');
CREATE TABLE payment_transactions (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id),
  subscription_id BIGINT REFERENCES subscriptions(id),
  provider payment_provider NOT NULL,
  context payment_context NOT NULL,
  provider_payment_id VARCHAR(255) UNIQUE,
  external_reference UUID NOT NULL UNIQUE DEFAULT gen_random_uuid(),
  amount_cents INTEGER NOT NULL CHECK (amount_cents > 0),
  provider_fee_cents INTEGER NOT NULL DEFAULT 0 CHECK (provider_fee_cents >= 0),
  status payment_status NOT NULL DEFAULT 'pending',
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), approved_at TIMESTAMPTZ,
  CHECK (
    (context = 'subscription' AND subscription_id IS NOT NULL AND provider = 'mercadopago')
    OR (context = 'marketplace' AND subscription_id IS NULL AND provider = 'pagseguro')
  )
);
CREATE TABLE webhook_events (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  provider payment_provider NOT NULL,
  request_id VARCHAR(255) NOT NULL,
  resource_id VARCHAR(255) NOT NULL,
  received_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  processed_at TIMESTAMPTZ,
  UNIQUE(provider,request_id)
);
CREATE TABLE wallets (
  id BIGINT PRIMARY KEY,
  user_id BIGINT UNIQUE REFERENCES users(id),
  kind VARCHAR(20) NOT NULL CHECK (kind IN ('platform','creator')),
  available_cents BIGINT NOT NULL DEFAULT 0 CHECK (available_cents >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK ((id = 1 AND kind = 'platform' AND user_id IS NULL) OR (id <> 1 AND kind = 'creator' AND user_id IS NOT NULL))
);
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
INSERT INTO wallets (id,user_id,kind) VALUES (1,NULL,'platform');
CREATE TABLE wallet_ledger (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  wallet_id BIGINT NOT NULL REFERENCES wallets(id),
  transaction_id BIGINT NOT NULL REFERENCES payment_transactions(id),
  entry_type VARCHAR(20) NOT NULL CHECK (entry_type IN ('platform_fee','creator_credit','withdrawal','reversal')),
  amount_cents BIGINT NOT NULL CHECK (amount_cents <> 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (wallet_id,transaction_id,entry_type)
);
CREATE TABLE content_profiles (
  user_id BIGINT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  display_name VARCHAR(80) NOT NULL,
  bio TEXT, photo_url VARCHAR(500), is_public BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE relationship_profiles (
  user_id BIGINT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  display_name VARCHAR(80) NOT NULL,
  bio TEXT, photo_url VARCHAR(500), city VARCHAR(100), relationship_goal VARCHAR(120),
  show_city BOOLEAN NOT NULL DEFAULT true, is_active BOOLEAN NOT NULL DEFAULT false,
  discovery_min_age SMALLINT NOT NULL DEFAULT 18 CHECK (discovery_min_age BETWEEN 18 AND 99),
  discovery_max_age SMALLINT NOT NULL DEFAULT 99 CHECK (discovery_max_age BETWEEN 18 AND 99),
  discovery_city VARCHAR(100), CHECK (discovery_min_age <= discovery_max_age),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE content_posts (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  producer_id BIGINT NOT NULL REFERENCES users(id),
  title VARCHAR(160) NOT NULL, description TEXT, access_type access_kind NOT NULL DEFAULT 'free',
  price_cents INTEGER CHECK (price_cents IS NULL OR price_cents > 0),
  is_adult BOOLEAN NOT NULL DEFAULT false, visibility VARCHAR(20) NOT NULL DEFAULT 'public',
  status VARCHAR(20) NOT NULL DEFAULT 'draft', created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE content_purchases (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  content_id BIGINT NOT NULL REFERENCES content_posts(id),
  buyer_id BIGINT NOT NULL REFERENCES users(id),
  transaction_id BIGINT UNIQUE REFERENCES payment_transactions(id),
  status payment_status NOT NULL DEFAULT 'pending',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), approved_at TIMESTAMPTZ,
  UNIQUE(content_id,buyer_id)
);
CREATE INDEX content_posts_monthly_limit ON content_posts (producer_id, created_at) WHERE status <> 'archived';
-- Conteúdo gratuito tem teto de 10 publicações por mês; criadores não têm esse teto.
CREATE OR REPLACE FUNCTION enforce_monthly_post_limit() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE selected_plan plan_code; monthly_total INTEGER;
BEGIN
  SELECT plan INTO selected_plan FROM account_plans WHERE user_id=NEW.producer_id;
  IF selected_plan NOT IN ('content_free','creator') THEN RAISE EXCEPTION 'Plano não permite publicar conteúdo'; END IF;
  IF selected_plan='content_free' THEN
    SELECT count(*) INTO monthly_total FROM content_posts WHERE producer_id=NEW.producer_id AND created_at >= date_trunc('month',NOW()) AND status <> 'archived';
    IF monthly_total >= 10 THEN RAISE EXCEPTION 'Limite mensal de 10 publicações atingido'; END IF;
  END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER content_posts_plan_limit BEFORE INSERT ON content_posts FOR EACH ROW EXECUTE FUNCTION enforce_monthly_post_limit();
CREATE TABLE content_accesses (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  content_id BIGINT NOT NULL REFERENCES content_posts(id), viewer_id BIGINT REFERENCES users(id),
  is_valid BOOLEAN NOT NULL DEFAULT false, accessed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE content_media (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  content_id BIGINT NOT NULL REFERENCES content_posts(id) ON DELETE CASCADE,
  storage_key VARCHAR(120) NOT NULL UNIQUE, original_name VARCHAR(255) NOT NULL,
  mime_type VARCHAR(100) NOT NULL, size_bytes BIGINT NOT NULL CHECK (size_bytes > 0 AND size_bytes <= 52428800),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE content_safety_reviews (
  content_id BIGINT PRIMARY KEY REFERENCES content_posts(id) ON DELETE CASCADE,
  provider VARCHAR(30) NOT NULL, decision VARCHAR(20) NOT NULL CHECK (decision IN ('approved','manual_review','rejected','error')),
  signals JSONB NOT NULL DEFAULT '[]'::jsonb, reviewed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE identity_verification_documents (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  storage_key VARCHAR(120) NOT NULL UNIQUE, mime_type VARCHAR(100) NOT NULL, status VARCHAR(20) NOT NULL DEFAULT 'pending_review',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), reviewed_at TIMESTAMPTZ
);
CREATE TABLE content_likes (
  content_id BIGINT NOT NULL REFERENCES content_posts(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), PRIMARY KEY(content_id,user_id)
);
CREATE TABLE content_comments (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  content_id BIGINT NOT NULL REFERENCES content_posts(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES users(id), body VARCHAR(1000) NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'published', created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (length(trim(body)) > 0)
);
CREATE TABLE hashtags (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  slug VARCHAR(80) NOT NULL UNIQUE CHECK (slug ~ '^[a-z0-9_]+$'),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE content_hashtags (
  content_id BIGINT NOT NULL REFERENCES content_posts(id) ON DELETE CASCADE,
  hashtag_id BIGINT NOT NULL REFERENCES hashtags(id) ON DELETE CASCADE,
  PRIMARY KEY(content_id,hashtag_id)
);
CREATE INDEX content_hashtags_tag ON content_hashtags(hashtag_id,content_id);
CREATE TABLE communities (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  owner_id BIGINT NOT NULL REFERENCES users(id),
  name VARCHAR(100) NOT NULL, slug VARCHAR(100) NOT NULL UNIQUE,
  description TEXT, visibility VARCHAR(20) NOT NULL DEFAULT 'public' CHECK (visibility IN ('public','private')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE community_members (
  community_id BIGINT NOT NULL REFERENCES communities(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role VARCHAR(20) NOT NULL DEFAULT 'member' CHECK (role IN ('owner','moderator','member')),
  joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), PRIMARY KEY(community_id,user_id)
);
CREATE TABLE community_posts (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  community_id BIGINT NOT NULL REFERENCES communities(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES users(id),
  body VARCHAR(2000) NOT NULL, status VARCHAR(20) NOT NULL DEFAULT 'published',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), CHECK (length(trim(body)) > 0)
);
CREATE INDEX community_posts_timeline ON community_posts(community_id,created_at DESC);
CREATE INDEX idx_content_accesses_viewer ON content_accesses (viewer_id, content_id, accessed_at DESC);
CREATE TABLE blocks (
  blocker_id BIGINT NOT NULL REFERENCES users(id), blocked_id BIGINT NOT NULL REFERENCES users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), PRIMARY KEY (blocker_id, blocked_id), CHECK (blocker_id <> blocked_id)
);
CREATE TABLE friendships (
  user_low_id BIGINT NOT NULL REFERENCES users(id),
  user_high_id BIGINT NOT NULL REFERENCES users(id),
  requester_id BIGINT NOT NULL REFERENCES users(id),
  status VARCHAR(12) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','accepted','declined','cancelled')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), responded_at TIMESTAMPTZ,
  PRIMARY KEY (user_low_id,user_high_id),
  CHECK (user_low_id < user_high_id),
  CHECK (requester_id IN (user_low_id,user_high_id))
);
CREATE INDEX friendships_incoming ON friendships (user_high_id,status);
CREATE TABLE relationship_interests (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  from_user_id BIGINT NOT NULL REFERENCES users(id), to_user_id BIGINT NOT NULL REFERENCES users(id),
  origin interest_origin NOT NULL, status interest_status NOT NULL DEFAULT 'pending',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), responded_at TIMESTAMPTZ,
  UNIQUE (from_user_id, to_user_id), CHECK (from_user_id <> to_user_id)
);
CREATE TABLE matches (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_low_id BIGINT NOT NULL REFERENCES users(id), user_high_id BIGINT NOT NULL REFERENCES users(id),
  origin interest_origin NOT NULL, status match_status NOT NULL DEFAULT 'active',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), ended_at TIMESTAMPTZ,
  UNIQUE(user_low_id,user_high_id), CHECK (user_low_id < user_high_id)
);
CREATE TABLE match_messages (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  match_id BIGINT NOT NULL REFERENCES matches(id) ON DELETE CASCADE,
  sender_id BIGINT NOT NULL REFERENCES users(id),
  body VARCHAR(2000) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (length(trim(body)) > 0)
);
CREATE INDEX idx_match_messages_timeline ON match_messages (match_id, created_at);
CREATE TABLE reports (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, reporter_id BIGINT NOT NULL REFERENCES users(id),
  reported_user_id BIGINT REFERENCES users(id), category VARCHAR(50) NOT NULL, details TEXT,
  reported_content_id BIGINT REFERENCES content_posts(id),
  status VARCHAR(20) NOT NULL DEFAULT 'open', created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_reports_triage ON reports (status, created_at);
CREATE TABLE notifications (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type VARCHAR(40) NOT NULL, title VARCHAR(160) NOT NULL, body TEXT,
  url VARCHAR(500), read_at TIMESTAMPTZ, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX notifications_unread ON notifications (user_id, created_at DESC) WHERE read_at IS NULL;
CREATE TABLE audit_logs (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  actor_id BIGINT REFERENCES users(id), action VARCHAR(80) NOT NULL,
  subject_type VARCHAR(50), subject_id BIGINT, metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX audit_logs_subject ON audit_logs (subject_type,subject_id,created_at DESC);
CREATE INDEX idx_accesses_producer_lookup ON content_accesses (content_id, viewer_id) WHERE is_valid;
CREATE INDEX idx_interests_recipient ON relationship_interests (to_user_id, status);

CREATE OR REPLACE FUNCTION create_user_settings() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN INSERT INTO user_settings (user_id) VALUES (NEW.id); RETURN NEW; END; $$;
CREATE TRIGGER users_settings_after_insert AFTER INSERT ON users FOR EACH ROW EXECUTE FUNCTION create_user_settings();
CREATE OR REPLACE FUNCTION create_default_account_plan() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN INSERT INTO account_plans (user_id,plan) VALUES (NEW.id,'relationship_free'); RETURN NEW; END; $$;
CREATE TRIGGER users_plan_after_insert AFTER INSERT ON users FOR EACH ROW EXECUTE FUNCTION create_default_account_plan();


-- Precedência: bloqueio invalida todo interesse e match entre o par.
CREATE OR REPLACE FUNCTION invalidate_blocked_interactions() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  UPDATE relationship_interests SET status='invalidated', responded_at=NOW()
   WHERE (from_user_id=NEW.blocker_id AND to_user_id=NEW.blocked_id) OR (from_user_id=NEW.blocked_id AND to_user_id=NEW.blocker_id);
  UPDATE matches SET status='blocked', ended_at=NOW()
   WHERE user_low_id=LEAST(NEW.blocker_id,NEW.blocked_id) AND user_high_id=GREATEST(NEW.blocker_id,NEW.blocked_id) AND status='active';
  UPDATE friendships SET status='cancelled', responded_at=NOW()
   WHERE user_low_id=LEAST(NEW.blocker_id,NEW.blocked_id) AND user_high_id=GREATEST(NEW.blocker_id,NEW.blocked_id) AND status IN ('pending','accepted');
  RETURN NEW;
END; $$;
CREATE TRIGGER blocks_invalidate AFTER INSERT ON blocks FOR EACH ROW EXECUTE FUNCTION invalidate_blocked_interactions();

-- Suspensão ou encerramento encerra exposição e impede novas interações.
CREATE OR REPLACE FUNCTION disable_inactive_account_interactions() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status <> 'active' AND OLD.status = 'active' THEN
    UPDATE user_settings SET content_enabled=false, dating_enabled=false, integration_enabled=false, visitor_identity_consent=false WHERE user_id=NEW.id;
    UPDATE relationship_profiles SET is_active=false WHERE user_id=NEW.id;
    UPDATE relationship_interests SET status='invalidated', responded_at=NOW() WHERE from_user_id=NEW.id OR to_user_id=NEW.id;
    UPDATE matches SET status='unmatched', ended_at=NOW() WHERE (user_low_id=NEW.id OR user_high_id=NEW.id) AND status='active';
  END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER users_disable_interactions AFTER UPDATE OF status ON users FOR EACH ROW EXECUTE FUNCTION disable_inactive_account_interactions();

-- A confirmação de marketplace credita 7% à carteira interna id=1 e 93% ao criador.
CREATE OR REPLACE FUNCTION distribute_marketplace_payment(payment_id BIGINT, creator_id BIGINT) RETURNS void LANGUAGE plpgsql AS $$
DECLARE gross INTEGER; provider_fee INTEGER; fee INTEGER; creator_wallet BIGINT;
BEGIN
  SELECT amount_cents,provider_fee_cents INTO gross,provider_fee FROM payment_transactions WHERE id=payment_id AND status='approved' AND context='marketplace' AND provider='pagseguro';
  IF gross IS NULL THEN RAISE EXCEPTION 'Pagamento não aprovado'; END IF;
  fee := ROUND(gross * 0.07);
  IF gross - fee - provider_fee < 0 THEN RAISE EXCEPTION 'Taxas excedem o valor do pagamento'; END IF;
  INSERT INTO wallets(id,user_id,kind) VALUES (creator_id + 1000000,creator_id,'creator') ON CONFLICT (user_id) DO NOTHING;
  SELECT id INTO creator_wallet FROM wallets WHERE user_id=creator_id;
  INSERT INTO wallet_ledger(wallet_id,transaction_id,entry_type,amount_cents) VALUES
    (1,payment_id,'platform_fee',fee),(creator_wallet,payment_id,'creator_credit',gross-fee-provider_fee)
  ON CONFLICT DO NOTHING;
  UPDATE wallets SET available_cents=available_cents+fee WHERE id=1;
  UPDATE wallets SET available_cents=available_cents+(gross-fee-provider_fee) WHERE id=creator_wallet;
END; $$;

-- Conversa só existe em match ativo e somente os participantes podem enviar mensagens.
CREATE OR REPLACE FUNCTION validate_match_message() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM matches WHERE id=NEW.match_id AND status='active'
                 AND NEW.sender_id IN (user_low_id,user_high_id)) THEN
    RAISE EXCEPTION 'Mensagem não permitida para este match';
  END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER match_messages_validate BEFORE INSERT ON match_messages FOR EACH ROW EXECUTE FUNCTION validate_match_message();
