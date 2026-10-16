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
