-- MyMatch: PostgreSQL 16+. As regras críticas são reforçadas também na camada PHP.
CREATE TYPE account_status AS ENUM ('active', 'suspended', 'closed');
CREATE TYPE access_kind AS ENUM ('free', 'single_purchase', 'subscription');
CREATE TYPE interest_origin AS ENUM ('discovery', 'content_visit');
CREATE TYPE interest_status AS ENUM ('pending', 'accepted', 'dismissed', 'invalidated', 'expired');
CREATE TYPE match_status AS ENUM ('active', 'unmatched', 'blocked');

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
CREATE TABLE user_settings (
  user_id BIGINT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  content_enabled BOOLEAN NOT NULL DEFAULT false,
  dating_enabled BOOLEAN NOT NULL DEFAULT false,
  integration_enabled BOOLEAN NOT NULL DEFAULT false,
  visitor_identity_consent BOOLEAN NOT NULL DEFAULT false,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (NOT integration_enabled OR dating_enabled)
);
CREATE TABLE content_profiles (
  user_id BIGINT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  display_name VARCHAR(80) NOT NULL,
  bio TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE relationship_profiles (
  user_id BIGINT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  display_name VARCHAR(80) NOT NULL,
  bio TEXT, city VARCHAR(100), is_active BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE content_posts (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  producer_id BIGINT NOT NULL REFERENCES users(id),
  title VARCHAR(160) NOT NULL, description TEXT, access_type access_kind NOT NULL DEFAULT 'free',
  is_adult BOOLEAN NOT NULL DEFAULT false, visibility VARCHAR(20) NOT NULL DEFAULT 'public',
  status VARCHAR(20) NOT NULL DEFAULT 'draft', created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE content_accesses (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  content_id BIGINT NOT NULL REFERENCES content_posts(id), viewer_id BIGINT REFERENCES users(id),
  is_valid BOOLEAN NOT NULL DEFAULT false, accessed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_content_accesses_viewer ON content_accesses (viewer_id, content_id, accessed_at DESC);
CREATE TABLE blocks (
  blocker_id BIGINT NOT NULL REFERENCES users(id), blocked_id BIGINT NOT NULL REFERENCES users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), PRIMARY KEY (blocker_id, blocked_id), CHECK (blocker_id <> blocked_id)
);
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
  status VARCHAR(20) NOT NULL DEFAULT 'open', created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_reports_triage ON reports (status, created_at);
CREATE INDEX idx_accesses_producer_lookup ON content_accesses (content_id, viewer_id) WHERE is_valid;
CREATE INDEX idx_interests_recipient ON relationship_interests (to_user_id, status);

CREATE OR REPLACE FUNCTION create_user_settings() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN INSERT INTO user_settings (user_id) VALUES (NEW.id); RETURN NEW; END; $$;
CREATE TRIGGER users_settings_after_insert AFTER INSERT ON users FOR EACH ROW EXECUTE FUNCTION create_user_settings();

-- Precedência: bloqueio invalida todo interesse e match entre o par.
CREATE OR REPLACE FUNCTION invalidate_blocked_interactions() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  UPDATE relationship_interests SET status='invalidated', responded_at=NOW()
   WHERE (from_user_id=NEW.blocker_id AND to_user_id=NEW.blocked_id) OR (from_user_id=NEW.blocked_id AND to_user_id=NEW.blocker_id);
  UPDATE matches SET status='blocked', ended_at=NOW()
   WHERE user_low_id=LEAST(NEW.blocker_id,NEW.blocked_id) AND user_high_id=GREATEST(NEW.blocker_id,NEW.blocked_id) AND status='active';
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
