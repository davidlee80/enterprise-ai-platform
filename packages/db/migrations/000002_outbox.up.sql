BEGIN;

CREATE TABLE outbox_event (
  event_id UUID PRIMARY KEY,
  event_type TEXT NOT NULL CHECK (length(event_type) > 0),
  schema_version INT NOT NULL CHECK (schema_version > 0),
  occurred_at TIMESTAMPTZ NOT NULL,
  tenant_id UUID REFERENCES tenant(id),
  request_id TEXT,
  trace_id TEXT,
  producer TEXT NOT NULL CHECK (length(producer) > 0),
  payload JSONB NOT NULL CHECK (jsonb_typeof(payload) = 'object'),
  available_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  attempt_count INT NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
  lease_owner TEXT,
  lease_token UUID,
  lease_expires_at TIMESTAMPTZ,
  published_at TIMESTAMPTZ,
  last_reason_code TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (
    (lease_owner IS NULL AND lease_token IS NULL AND lease_expires_at IS NULL)
    OR
    (lease_owner IS NOT NULL AND lease_token IS NOT NULL AND lease_expires_at IS NOT NULL)
  ),
  CHECK (
    published_at IS NULL
    OR (lease_owner IS NULL AND lease_token IS NULL AND lease_expires_at IS NULL)
  )
);

CREATE INDEX outbox_event_pending_idx
  ON outbox_event (available_at, occurred_at, event_id)
  WHERE published_at IS NULL;

CREATE FUNCTION enqueue_outbox_event(
  p_event_id UUID,
  p_event_type TEXT,
  p_schema_version INT,
  p_occurred_at TIMESTAMPTZ,
  p_tenant_id UUID,
  p_request_id TEXT,
  p_trace_id TEXT,
  p_producer TEXT,
  p_payload JSONB
) RETURNS UUID
LANGUAGE SQL
AS $$
  INSERT INTO outbox_event (
    event_id,
    event_type,
    schema_version,
    occurred_at,
    tenant_id,
    request_id,
    trace_id,
    producer,
    payload
  ) VALUES (
    p_event_id,
    p_event_type,
    p_schema_version,
    p_occurred_at,
    p_tenant_id,
    p_request_id,
    p_trace_id,
    p_producer,
    p_payload
  )
  RETURNING event_id;
$$;

CREATE FUNCTION claim_outbox_events(
  p_worker_id TEXT,
  p_lease_token UUID,
  p_limit INT,
  p_now TIMESTAMPTZ,
  p_lease_until TIMESTAMPTZ
) RETURNS SETOF outbox_event
LANGUAGE SQL
AS $$
  WITH candidates AS (
    SELECT event_id
    FROM outbox_event
    WHERE published_at IS NULL
      AND available_at <= p_now
      AND (lease_expires_at IS NULL OR lease_expires_at <= p_now)
      AND p_limit > 0
      AND p_lease_until > p_now
    ORDER BY occurred_at, event_id
    FOR UPDATE SKIP LOCKED
    LIMIT p_limit
  )
  UPDATE outbox_event AS event
  SET lease_owner = p_worker_id,
      lease_token = p_lease_token,
      lease_expires_at = p_lease_until,
      attempt_count = event.attempt_count + 1,
      last_reason_code = NULL
  FROM candidates
  WHERE event.event_id = candidates.event_id
  RETURNING event.*;
$$;

CREATE FUNCTION mark_outbox_event_published(
  p_event_id UUID,
  p_lease_token UUID,
  p_published_at TIMESTAMPTZ
) RETURNS BOOLEAN
LANGUAGE SQL
AS $$
  WITH updated AS (
    UPDATE outbox_event
    SET published_at = p_published_at,
        lease_owner = NULL,
        lease_token = NULL,
        lease_expires_at = NULL,
        last_reason_code = NULL
    WHERE event_id = p_event_id
      AND lease_token = p_lease_token
      AND published_at IS NULL
    RETURNING event_id
  )
  SELECT EXISTS (SELECT 1 FROM updated);
$$;

CREATE FUNCTION release_outbox_event(
  p_event_id UUID,
  p_lease_token UUID,
  p_available_at TIMESTAMPTZ,
  p_reason_code TEXT
) RETURNS BOOLEAN
LANGUAGE SQL
AS $$
  WITH updated AS (
    UPDATE outbox_event
    SET available_at = p_available_at,
        lease_owner = NULL,
        lease_token = NULL,
        lease_expires_at = NULL,
        last_reason_code = p_reason_code
    WHERE event_id = p_event_id
      AND lease_token = p_lease_token
      AND published_at IS NULL
      AND p_reason_code IS NOT NULL
      AND length(p_reason_code) > 0
    RETURNING event_id
  )
  SELECT EXISTS (SELECT 1 FROM updated);
$$;

REVOKE ALL ON FUNCTION enqueue_outbox_event(
  UUID, TEXT, INT, TIMESTAMPTZ, UUID, TEXT, TEXT, TEXT, JSONB
) FROM PUBLIC;
REVOKE ALL ON FUNCTION claim_outbox_events(
  TEXT, UUID, INT, TIMESTAMPTZ, TIMESTAMPTZ
) FROM PUBLIC;
REVOKE ALL ON FUNCTION mark_outbox_event_published(
  UUID, UUID, TIMESTAMPTZ
) FROM PUBLIC;
REVOKE ALL ON FUNCTION release_outbox_event(
  UUID, UUID, TIMESTAMPTZ, TEXT
) FROM PUBLIC;

INSERT INTO schema_migration (version, description, content_hash)
VALUES ('000002', 'REQ-DB-008 transactional outbox boundary', :'migration_hash');

COMMIT;
