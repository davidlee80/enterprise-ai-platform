BEGIN;

CREATE TABLE schema_migration (
  version TEXT PRIMARY KEY,
  description TEXT NOT NULL,
  content_hash TEXT NOT NULL,
  applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE tenant (
  id UUID PRIMARY KEY,
  name TEXT NOT NULL,
  plan TEXT NOT NULL,
  status TEXT NOT NULL,
  budget_monthly NUMERIC(18,6),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE provider_endpoint (
  id UUID PRIMARY KEY,
  provider_name TEXT NOT NULL,
  region TEXT NOT NULL,
  endpoint TEXT NOT NULL,
  secret_ref TEXT NOT NULL,
  priority INT NOT NULL DEFAULT 100,
  weight INT NOT NULL DEFAULT 100,
  enabled BOOLEAN NOT NULL DEFAULT true,
  config_version BIGINT NOT NULL DEFAULT 1
);

CREATE TABLE model_route (
  id UUID PRIMARY KEY,
  tenant_id UUID REFERENCES tenant(id),
  model_alias TEXT NOT NULL,
  provider_endpoint_id UUID REFERENCES provider_endpoint(id),
  provider_model TEXT NOT NULL,
  strategy TEXT NOT NULL,
  weight INT NOT NULL DEFAULT 100,
  priority INT NOT NULL DEFAULT 100,
  enabled BOOLEAN NOT NULL DEFAULT true
);

INSERT INTO schema_migration (version, description, content_hash)
VALUES ('000001', 'REQ-DB-001 through REQ-DB-003 baseline', :'migration_hash');

COMMIT;

